#!/usr/bin/env ruby

require "parseconfig"

def getFirstOr(a,alt)
  return alt if a == nil 
  return alt if a.empty?
  a.first
end

def getArgs(&f)
  ARGV.map{|a|
    f.call(a)
  }.compact
end


class FileViewer
  attr :args

  def initialize
    parseArgs
    @args["files"].each{|f|
      mime = getMime(f)
      runner = updateRunner( mime )
      exec = fillRunnerArgs( f, runner )
      `#{exec}`
    }
  end

  def getMime( file )
    mime = `xdg-mime query filetype "#{file}"`.chomp
    p "got mime: #{mime}"
    mime
  end

  def parseArgs
    @args = {
      "icon"    => "",
      "caption" => "v",
      "db"      => [],
      "factor"  => [],
      "files"   => []
    }
    
    @args["files"] = getArgs{ |c|
      cf = File.expand_path(c)
      File.exists?( cf ) ? cf : nil 
    }

    @args["db"] = getArgs{ |c|
      m = /^([+-][0-9]+)db$/i.match(c)
      m == nil ? nil : m[1]
    }

    @args["factor"] = getArgs{ |c|
      m = /^([0-9]+[.][0-9]+)x$/i.match(c)
      m == nil ? nil : m[1]
    }

    if @args["files"].empty?
      p "use with any file..."
      exit 0
    end
  end

  def getMimeRunnerFor( desktopFile )
    defaultMimePath = "/usr/share/applications/"
    path = defaultMimePath + desktopFile

    # sometimes files have this form: kde4-gwenview.desktop => kde4/gwenview.desktop
    if !File.exists?(path)
      parts = desktopFile.split("-")
      if parts.length >= 2
        path = defaultMimePath + parts[0] + "/" + parts.drop(1).join("-")
      end
    end

    return nil if !File.exists?(path)
    conf = ParseConfig.new( path )
    conf.params["Desktop Entry"]["Exec"]
  end

  def guessMimeRunnerFor( desktopFile )
    desktopFile.gsub(/.desktop$/,"") + " %U "
  end

  def getMimeRunnerFromConfig( mime, configfile, key )
    conf = ParseConfig.new( configfile )
    apps = conf.params[key][mime]
    return nil if apps == nil 
    desktopFile = apps.split(";")[0]

    # get the runner
    runner = getMimeRunnerFor( desktopFile )
    runner = guessMimeRunnerFor( desktopFile ) if runner == nil
    runner
  end

  def getFromMimeinfo( mime )
    getMimeRunnerFromConfig mime, "/usr/share/applications/mimeinfo.cache", "MIME Cache"
  end

  def getFromLocalMimeappList( mime )
    getMimeRunnerFromConfig mime, File.expand_path( "~/.local/share/applications/mimeapps.list" ), "Default Applications"
  end

  def adjustRunner( r ) 
    if r.match(/^mplayer/)
      speed = getFirstOr( @args["factor"], "1.0" )
      db = getFirstOr( @args["db"], "+0" )
      "#{r} -af volume=#{db}dB,scaletempo -speed #{speed} "
    else r
    end
  end

  def updateRunner( mime )
    runner = nil
    runner = getFromLocalMimeappList mime if runner == nil
    runner = getFromMimeinfo mime if runner == nil
    runner = adjustRunner runner
  end

  def fillRunnerArgs( file, runner )
    runner = runner.
      gsub( /%F/, "\"" + file + "\"" ).
      gsub( /%U/, "\"" + file + "\"" ).
      gsub( /%i/, @args["icon"] ).
      gsub( /%c/, @args["caption"] )
    p "got runner: #{runner}"
    runner
  end

end

FileViewer.new