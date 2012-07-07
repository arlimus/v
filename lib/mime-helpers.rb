#!/usr/bin/env ruby

require "parseconfig"

module MimeHelpers

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
  def getRunner( mime )
    runner =  getRunnerFromMimeappList( mime ) ||
              getRunnerFromMimeinfoCache( mime ) ||
              nil
    return nil if runner.nil?
    runner = tweakRunner runner
  end

  # Take a runner and fill the placeholders with actual arguments.
  # e.g.:    mplayer %F
  # becomes: mplayer myfile.mkv
  def fillRunnerArgs( runner, file )
    runner = runner.
      gsub( /%F/, "\"" + file + "\"" ).
      gsub( /%U/, "\"" + file + "\"" ).
      gsub( /%u/, "\"" + file + "\"" ).
      gsub( /%i/, @args["icon"] ).
      gsub( /%c/, @args["caption"] )
    runner
  end



  private

  mimeRunnerPath = "/usr/share/applications/"

  # scan a mime config file and find the execution line
  # e.g. for "mplayer.desktop"
  # return "mplayer %F "
  def getMimeRunnerFor( desktopFile )
    path = mimeRunnerPath + desktopFile

    # sometimes files have this form: kde4-gwenview.desktop => kde4/gwenview.desktop
    if !File.exists?(path)
      parts = desktopFile.split("-")
      if parts.length >= 2
        path = mimeRunnerPath + parts[0] + "/" + parts.drop(1).join("-")
      end
    end

    return nil if !File.exists?(path)
    conf = ParseConfig.new( path )
    conf.params["Desktop Entry"]["Exec"]
  end

  # e.g. for "mplayer.desktop" guess "mplayer"
  def guessMimeRunnerFor( desktopFile )
    desktopFile.gsub(/.desktop$/,"") + " %F "
  end

  # e.g.:    for 'video/x-matroska', "/usr/share/applications/mimeinfo.cache", "MIME Cache"
  # returns: 'mplayer.desktop' 
  def getRunnerMetaFromConfig( mime, configfile, key )
    begin
      conf = ParseConfig.new( configfile )
      apps = conf.params[key][mime]
      return nil if apps == nil 
      return apps.split(";")[0]
    rescue
      return nil
    end
  end

  # For a given mime-type, find the system's execution line. Scans a given configfile and key
  # e.g.:    for 'video/x-matroska', "/usr/share/applications/mimeinfo.cache", "MIME Cache"
  # returns: mplayer %F 
  def getRunnerFromConfig( mime, configfile, key )
    desktopFile = getRunnerMetaFromConfig mime, configfile, key
    return nil if desktopFile.nil?
    puts "-- desktop file found for mime '#{mime}' in #{configfile} (key: '#{key}')" if @opts[:verbose]

    # get the runner
    runner = getMimeRunnerFor( desktopFile )
    return runner if not runner.nil?

    # if something went wrong, try to guess it:
    runner = guessMimeRunnerFor( desktopFile )
    puts "-- guessing runner via #{desktopFile}, got: '#{runner}'" if not runner.nil? and @opts[:verbose]
    runner
  end

  def getRunnerFromMimeinfoCache( mime )
    key = "MIME Cache"
    path = "share/applications/mimeinfo.cache"
    return  getRunnerFromConfig( mime, File.expand_path( "~/.local/#{path}" ), key) ||
            getRunnerFromConfig( mime, "/usr/#{path}", key)
  end

  def getRunnerFromMimeappList( mime )
    key = "Default Applications"
    path = "share/applications/mimeapps.list"
    return  getRunnerFromConfig( mime, File.expand_path( "~/.local/#{path}" ), key) ||
            getRunnerFromConfig( mime, "/usr/#{path}", key)
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
  def tweakRunner( r ) 
    if r.match(/^mplayer/)
      speed = getFirstOr( @args["factor"], "1.0" )
      db = getFirstOr( @args["db"], "+0" )
      "#{r} -af volume=#{db}dB,scaletempo -speed #{speed} "
    else r
    end
  end

end
