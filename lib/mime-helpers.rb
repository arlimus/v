#!/usr/bin/env ruby

require "parseconfig"
require "yaml"
require "zlog"

module MimeHelpers

  @opts = {
    :pretend => nil
  }

  # for a given file, return the mime-type
  # e.g. for "vid.mkv" returns "video/x-matroska"
  def getMime( file )
    return nil if file.nil? or file.empty? or not File::exists?(file)
    return validate_mime( `file --mime-type --br "#{file}"`.strip, file )
  end

  # For a given mime-type, find the system's execution line. Scan all relevant files.
  # e.g.:    for 'video/x-matroska'
  # returns: mplayer %F 
  def getRunner( mime, file, args )
    required = []
    files = Array(file)
    # if it's a folder, find its primary mime and refill required
    mime, required = dir_runner_and_required(
      file, mime, required ) if mime == "inode/directory"

    # find a runner for whatever mime is given
    runner = getRunnerFromAllLocalAndGlobal mime, required
    
    # if we didn't find a mime but we are checking a folder,
    # try directly executing matching files via their runner
    if runner.nil? and not required.empty?
      Zlog.debug "didn't find a runner for #{mime} that handles #{required}"
      runner = getRunnerFromAllLocalAndGlobal mime, []
      files = @mime_hash[mime].sort
    end

    ( Zlog.error "couldn't find a runner for #{mime}"
      return nil ) if runner.nil?
    Zlog.info "got runner '#{runner}' for #{file}"
    
    runner = tweakRunner runner, args
    fillRunnerArgs( runner, files, args )
  end

  # Take a runner and fill the placeholders with actual arguments.
  # e.g.:    mplayer %F
  # becomes: mplayer myfile.mkv
  def fillRunnerArgs( runner, files, args )
    file_line = "\"" + files.join("\" \"") + "\""
    runner = runner.
      gsub( /%F/, file_line ).
      gsub( /%U/, file_line ).
      gsub( /%u/, file_line ).
      gsub( /%i/, args["icon"] ).
      gsub( /%c/, args["caption"] )
    runner
  end



  private



  def dir_runner_and_required( path, mime_org, required )
    mime = dir_runner( path )
    return mime_org, required if mime.nil?

    Zlog.debug "dir_runner for #{path} got: #{mime}"
    return mime, ["inode/directory"]
  end 

  def dir_runner_readme(path)
    # find readme-type directory
    Zlog.debug "looking for readme file (dir-runner type readme)"
    readme = ["README","README.md","README.txt"].find_all{|f|
      File::exists?( File::expand_path( path + "/" +f ) )
    }
    return getMime( readme.first ) if not readme.empty?

    Zlog.debug "not a dir-runner type readme"
    nil
  end

  def get_all_file_types_for(path)
    Zlog.info "collecting files and determining mime types"

    # remove bad characters which hinder Dir from searching properly
    search_path = path.
                  gsub(/([\[\]*])/){ "\\#{$1}" } + "/*"
    Zlog.debug "search for files via: #{search_path}"
    dir_files = Dir[ search_path ]
    Zlog.debug "files to evaluate: #{dir_files}"

    # collect all file-types into a hash
    # type => [files]
    @mime_hash = {}
    dir_files.each do |f|
      key = getMime( f )
      @mime_hash[key] = Array(@mime_hash[key]).push f
    end
    Zlog.debug "got mimes for files:\n#{@mime_hash}"
  end

  def dir_runner_files(path)
    get_all_file_types_for(path)
    # find some combination of mime-types that fit a scheme
    keys = []
    keys = @mime_hash.keys.find_all{|e| not e.index("video").nil? } if keys.empty?
    keys = @mime_hash.keys.find_all{|e| not e.index("audio").nil? } if keys.empty?
    keys = @mime_hash.keys.find_all{|e| not e.index("image").nil? } if keys.empty?

    keys.first
  end

  def dir_runner(path)
    Zlog.debug "findDirRunner in #{path}"
    r = dir_runner_readme(path) || dir_runner_files(path) || nil
    Zlog.debug "findDirRunner finished for #{path}, got #{r}"
    r
  end


  MIME_UNKNOWN = [ "application/octet-stream" ]
  MIME_EXT = YAML.load_file(File.dirname(__FILE__) + '/mime_by_file_ending.yml')

  def validate_mime( m, path )
    Zlog.debug "got mime '#{m}' for #{path}, validating..."
    return m if not MIME_UNKNOWN.include?(m)
    ext = path.downcase.match(/(?=.)[a-z0-9]*$/).to_s
    Zlog.debug "mime '#{m}' is unkown, looking via file extension #{ext}"
    MIME_EXT[ ext ]
  end


  @@mimeRunnerPath = "/usr/share/applications/"

  # scan a mime config file and find the execution line
  # e.g. for "mplayer.desktop"
  # return "mplayer %F "
  def getMimeRunnerFor( desktopFile, must_support )
    path = @@mimeRunnerPath + desktopFile

    # sometimes files have this form: kde4-gwenview.desktop => kde4/gwenview.desktop
    if not File.exists?(path)
      parts = desktopFile.split("-")
      if parts.length >= 2
        path = @@mimeRunnerPath + parts[0] + "/" + parts.drop(1).join("-")
      end
    end

    if not File.exists?(path)
      Zlog.debug "Couldn't find runner in #{desktopFile} (#{path})"
      return nil
    end

    conf = ParseConfig.new( path )

    # look into supported mime types for this file
    mime_types = conf.params["Desktop Entry"]["MimeType"].
                      split(";").find_all{|e| not e.empty?}
    # check if compulsory mime types are included, if there are any
    compulsory =
      Array(must_support).compact.find_all{|e| not e.empty?}.
        map{|e| mime_types.include?(e) }
    ( 
      Zlog.info "can't use #{desktopFile}, it doesn't support #{must_support}"
      return nil 
    ) if not compulsory.find_all{|e| e == false}.empty?

    # get the execution line
    conf.params["Desktop Entry"]["Exec"]
  end

  # e.g. for "mplayer.desktop" guess "mplayer"
  def guessMimeRunnerFor( desktopFile )
    desktopFile.gsub(/.desktop$/,"") + " %F "
  end

  # e.g.:    for 'video/x-matroska', "/usr/share/applications/mimeinfo.cache", "MIME Cache"
  # returns: 'mplayer.desktop' 
  def getRunnerMetaFromConfig( mime, configfile, keys )
    keys = Array(keys).compact.find_all{|k| not k.empty?}
    begin
      conf = ParseConfig.new( configfile )
      keys.each{|key|
        apps = conf.params[key][mime]
        apps = apps.split(";").find_all{|e| not e.empty?} if not apps.nil?
        return apps,key if not apps.nil?
      }
      return [],nil
    rescue
      return [],nil
    end
  end

  # For a given mime-type, find the system's execution line. Scans a given configfile and key
  # e.g.:    for 'video/x-matroska', "/usr/share/applications/mimeinfo.cache", "MIME Cache"
  # returns: mplayer %F 
  def getRunnerFromConfig( mime, configfile, keys, must_support, guess = false )
    desktopFiles,key = getRunnerMetaFromConfig mime, configfile, keys
    return nil if desktopFiles.empty?

    desktopFiles.each do |desktopFile|
      Zlog.debug "desktop file '#{desktopFile}' found for '#{mime}' in #{configfile} (key: '#{key}')"

      # get the runner
      if not guess
        runner = getMimeRunnerFor( desktopFile, must_support )
      else
        Zlog.debug "guessing runner via #{desktopFile}, got: '#{runner}'" if not runner.nil?
        runner = guessMimeRunnerFor( desktopFile )
      end
      return runner if not runner.nil?
    end
    nil
  end

  def getRunnerFromLocalAndGlobal( mime, rel_path, keys, must_support )
    return (
      getRunnerFromConfig( mime, File.expand_path( "~/.local/#{rel_path}" ), keys, must_support) ||
      getRunnerFromConfig( mime, "/usr/#{rel_path}", keys, must_support)
    )
  end

  def getRunnerFromAllLocalAndGlobal(mime, must_support = [] )
    getRunnerFromLocalAndGlobal( mime,
      "share/applications/mimeapps.list",
      ["Default Applications","Added Associations"],
      must_support ) ||
    getRunnerFromLocalAndGlobal( mime,
      "share/applications/mimeinfo.cache",
      "MIME Cache",
      must_support ) ||
    nil
  end


  # For a given array, get the first entry or an alternative
  # e.g. getFirstOr(Array.new,1) returns 1
  # e.g. getFirstOr(Array.new(1,2),1) returns 2
  def getFirstOr(a,alt)
    return alt if a == nil 
    return alt if a.empty?
    a.first
  end

  # Some runners are adjusted
  # e.g. mplayer supports factor arguments for speed-stepping
  # so "v 1.5x myfile.mkv" will result in "mplayer -af scaletempo -speed 1.5 myfile.mkv"
  def tweakRunner( r, args ) 
    if r.match(/^mplayer/)
      speed = getFirstOr( args["factor"], "1.0" )
      db = getFirstOr( args["db"], "+0" )
      "#{r} -af volume=#{db}dB,scaletempo -speed #{speed} "
    else r
    end
  end

end
