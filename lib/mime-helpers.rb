#!/usr/bin/env ruby

require "parseconfig"
require "yaml"
require "zlog"

module MimeHelpers
  class << self
    # for a given file, return the mime-type
    # e.g. for "vid.mkv" returns "video/x-matroska"
    def getMime( file )
      return nil if file.nil? or file.empty? or not File::exists?(file)
      return "inode/directory" if File::directory?(file)
      return mime_by_file_ending file
    end

    # For a given mime-type, find the system's execution line. Scan all relevant files.
    # e.g.:    for 'video/x-matroska'
    # returns: mplayer %F
    def getRunner( mime, path, args )
      runner = nil

      # if we have a directory, try to find its dominant mime
      # in case we find anything, we will also supply the files that led to this decision
      dir_mime, files = ( mime == "inode/directory" ) ? dir_runner( path ) : [nil,[]]

      # in case we have a directory with a dominant mime
      if not dir_mime.nil?
        # get the runner that can handle both the dominant mime and the folder
        runner = getRunnerFromAllLocalAndGlobal dir_mime, [mime]
        # in case that didn't work (often, because the folder-mime isn't supported)
        if runner.nil?
          Zlog.debug "didn't find a runner for #{dir_mime} that works on #{mime}, trying override"
          # try getting a runner just for the mime, without directory as prerequisite
          runner = getRunnerFromAllLocalAndGlobal dir_mime, []
        else
          # in case we have a runner to handle inode/directory + contents,
          # empty out the list of files, since we will just run the directory
          # example: sublime supports various text-based files and folders
          #   files will be [some.md,some.txt,...] and a we have a runner for inode/directory
          #   instead of running sublime [some.md,...]
          #   instead run sublime <folder>
          files = []
        end
      end

      # find a runner for the mime
      # in case of folders: we only get here if we have no dominant mime
      # or couldn't find a runner for the dominant mime
      # => in both cases just treat it as a folder (which it is)
      runner = getRunnerFromAllLocalAndGlobal mime, [] if runner.nil?

      # success/failure messages
      ( Zlog.error "couldn't find a runner for #{mime}"
        return [ nil, files ] ) if runner.nil?
      Zlog.info "got runner '#{runner}' for #{path}"

      [ tweakRunner(runner, args), files ]
    end

    # Take a runner and fill the placeholders with actual arguments.
    # e.g.:    mplayer %F
    # becomes: mplayer myfile.mkv
    def fillRunnerArgs( runner, files, args )
      file_line = "\"" + files.sort.join("\" \"") + "\""
      runner = runner.
        gsub( /%F/, file_line ).
        gsub( /%U/, file_line ).
        gsub( /%u/, file_line ).
        gsub( /%i/, args["icon"] || "" ).
        gsub( /%c/, args["caption"] || "v" )
      runner
    end



    private



    def dir_runner_readme(path)
      # find readme-type directory
      Zlog.debug "looking for readme file (dir-runner type readme)"
      readme = ["README","README.md","README.txt"].map{|f|
          File::expand_path( path + "/" + f )
        }.find_all{|c|
          File::exists?(c)
        }

      return [ getMime( readme.first ), [readme.first] ] if not readme.empty?

      Zlog.debug "not a dir-runner type readme"
      [ nil, nil ]
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
      mime_hash = {}
      dir_files.each do |f|
        key = getMime( f )
        mime_hash[key] = Array(mime_hash[key]).push f if not key.nil?
      end
      Zlog.debug "got mimes for files:\n#{mime_hash}"
      mime_hash
    end

    def dir_runner_files(path)
      mime_hash = get_all_file_types_for(path)
      # find some combination of mime-types that fit a scheme
      keys = []
      keys = mime_hash.keys.find_all{|e| not e.index("video").nil? } if keys.empty?
      keys = mime_hash.keys.find_all{|e| not e.index("audio").nil? } if keys.empty?
      keys = mime_hash.keys.find_all{|e| not e.index("image").nil? } if keys.empty?
      keys = mime_hash.keys.find_all{|e| not e.index("text/").nil? } if keys.empty?

      [ keys.first, mime_hash.find_all{|k,v| k == keys.first }.map{|x|x[1]}.flatten ]
    end

    def dir_runner(path)
      Zlog.debug "findDirRunner in '#{path}'"
      r, files = dir_runner_readme(path)
      r, files = dir_runner_files(path) if r.nil?
      Zlog.info "dominant mime for '#{path}' is '#{r}'"
      [ r, files ]
    end


    MIME_UNKNOWN = [ "application/octet-stream" ]
    MIME_EXT = YAML.load_file(File.dirname(__FILE__) + '/mime_by_file_ending.yml')

    def mime_by_file_ending( path, failsafe = true )
      # move extensions forward if files are partial
      # from: some.avi.part
      # to:   some.avi
      # the latter can correctly detect the .avi extension
      path = path.gsub(/.part$/,'')
      # get the extension
      ext = path.downcase.match(/\.[a-z0-9]*$/).to_s[1..-1]
      # try to get the mime by extension
      m = MIME_EXT[ ext ]
      Zlog.debug "got mime '#{m}' for '#{path}' via file extension"
      return m if not m.nil?

      # we only get here if we couldn't find the mime type
      if failsafe
        Zlog.debug "mime '#{m}' is unkown..."
        return mime_by_magic_hash path, false
      else
        Zlog.warning "couldn't determine mime for '#{path}'"
        return nil
      end
    end

    def mime_by_magic_hash( path, failsafe = true )
      m = `file --mime-type --br "#{path}"`.strip
      Zlog.debug "got mime '#{m}' for '#{path}' via magic code"
      return m if not MIME_UNKNOWN.include?(m)

      # we only get here if we couldn't find the mime type
      if failsafe
        Zlog.debug "mime '#{m}' is unkown..."
        return mime_by_file_ending path, false
      else
        Zlog.warning "couldn't determine mime for '#{path}'"
        return nil
      end
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
    def getItemOr(a, idx, alt)
      return alt if a == nil
      return alt if idx >= a.length
      a[idx]
    end

    # Some runners are adjusted
    # e.g. mplayer supports factor arguments for speed-stepping
    # so "v 1.5x myfile.mkv" will result in "mplayer -af scaletempo -speed 1.5 myfile.mkv"
    def tweakRunner( r, args )
      if r.match(/^mplayer/)
        speed = getItemOr( args["factor"], 1, "1.0" )
        db = getItemOr( args["db"], 1, "+0" )
        novideo = ( args["novideo"].nil? ) ? "" : "-novideo"
        nosound = ( args["nosound"].nil? ) ? "" : "-nosound"
        nosub   = ( args["nosub"].nil? )   ? "" : "-nosub"
        r.gsub( /(mplayer[^ ]*\s)/ ){ "#{$1} -af volume=#{db}dB,scaletempo -speed #{speed} #{novideo} #{nosound} #{nosub} " }
      else r
      end
    end

  end
end
