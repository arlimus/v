#!/usr/bin/env ruby

require "parseconfig"

module MimeHelpers

  @opts = {
    :verbose => nil,
    :debug => nil,
    :pretend => nil
  }

  # for a given file, return the mime-type
  # e.g. for "vid.mkv" returns "video/x-matroska"
  def getMime( file )
    return nil if file.nil? or file.empty? or not File::exists?(file)
    mimeMatch = `file --mime "#{file}"`.match(/: ([^;]*)/)
    return nil if mimeMatch.nil?

    mimeMatch[1]
  end

  # For a given mime-type, find the system's execution line. Scan all relevant files.
  # e.g.:    for 'video/x-matroska'
  # returns: mplayer %F 
  def getRunner( mime, file, args )
    required = []
    mime, required = dir_runner_and_required(
      file, mime, required ) if mime == "inode/directory"

    runner = getRunnerFromAllLocalAndGlobal mime, required
    return nil if runner.nil?
    runner = tweakRunner runner, args
  end

  # Take a runner and fill the placeholders with actual arguments.
  # e.g.:    mplayer %F
  # becomes: mplayer myfile.mkv
  def fillRunnerArgs( runner, file, args )
    runner = runner.
      gsub( /%F/, "\"" + file + "\"" ).
      gsub( /%U/, "\"" + file + "\"" ).
      gsub( /%u/, "\"" + file + "\"" ).
      gsub( /%i/, args["icon"] ).
      gsub( /%c/, args["caption"] )
    runner
  end



  private

  def dir_runner_and_required( path, mime_org, required )
    mime = dir_runner( path )
    return mime_org, required if mime.nil?

    puts "dd dir_runner for #{path} got: #{mime}" if @opts[:debug]
    return mime, ["inode/directory"]
  end 

  def dir_runner_readme(path)
    # find readme-type directory
    readme = ["README","README.md","README.txt"].find_all{|f|
      File::exists?( File::expand_path( path + "/" +f ) )
    }
    return getMime( readme.first ) if not readme.empty?
    nil
  end

  def dir_runner(path)
    puts "dd findDirRunner in #{path}" if @opts[:debug]
    r = dir_runner_readme(path) || nil
    puts "dd findDirRunner finished for #{path}, got #{r}" if @opts[:debug]
    r
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

    return nil if not File.exists?(path)

    conf = ParseConfig.new( path )

    # look into supported mime types for this file
    mime_types = conf.params["Desktop Entry"]["MimeType"].
                      split(";").find_all{|e| not e.empty?}
    # check if compulsory mime types are included, if there are any
    compulsory =
      Array(must_support).compact.find_all{|e| not e.empty?}.
        map{|e| mime_types.include?(e) }
    ( puts "-- can't use #{desktopFile}, it doesn't support #{must_support}"
      return nil ) if not compulsory.find_all{|e| e == false}.empty?

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
      puts "-- desktop file '#{desktopFile}' found for '#{mime}' in #{configfile} (key: '#{key}')" if @opts[:verbose]

      # get the runner
      if not guess
        runner = getMimeRunnerFor( desktopFile, must_support )
      else
        puts "-- guessing runner via #{desktopFile}, got: '#{runner}'" if not runner.nil? and @opts[:verbose]
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
