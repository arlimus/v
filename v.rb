#!/usr/bin/env ruby

require "parseconfig"

def getFirstOr(a,alt)
  return alt if a == nil 
  return alt if a.empty?
  a[0]
end

def getArgs(&f)
  ARGV.map{|a|
    f.call(a)
  }.compact
end


class V
  attr :args, :runner, :mime

  def initialize
    parseArgs

    dstFile = @args["files"][0]
    @mime = `xdg-mime query filetype "#{dstFile}"`.chomp

    p "got mime: #{@mime}"
    updateRunner
    
    p "got runner: #{runner}"
    `#{runner} "#{dstFile}"`

  end

  def parseArgs
    @args = {}
    
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

  def getMimeFromConfigFile( mime, configfile, key )
    conf = ParseConfig.new( configfile )
    apps = conf.params[key][mime]
    return nil if apps == nil 
    apps.split(";")[0].gsub(".desktop","")
  end

  def getFromMimeinfo( mime )
    getMimeFromConfigFile mime, "/usr/share/applications/mimeinfo.cache", "MIME Cache"
  end

  def getFromLocalMimeappList( mime )
    getMimeFromConfigFile mime, File.expand_path( "~/.local/share/applications/mimeapps.list" ), "Default Applications"
  end

  def updateRunner
    runner = nil
    runner = getFromLocalMimeappList @mime if runner == nil
    runner = getFromMimeinfo @mime if runner == nil
    @runner = fixRunner runner
  end

  def fixRunner( r ) 
    # TODO: read from config
    r.gsub!("kde4-","")
    r.gsub!("sublime-text-dev","subl")

    if r == "mplayer"
      speed = getFirstOr( @args["factor"], "1.0" )
      db = getFirstOr( @args["db"], "+0" )
      "#{r} -af volume=#{db}dB,scaletempo -speed #{speed} "
    else r
    end
  end

end

V.new