#!/usr/bin/env ruby

require 'parseconfig'
require 'zlog'

class ArgumentParser
  def initialize( files = [] )
    default_configs = [ "lib/v.default.conf" ]
    @config = {}

    ( default_configs + files ).map do |f|
      Zlog.debug "load config from '#{f}'"
      ParseConfig::new(f)
    end.each{|cur| deep_merge( cur.params, @config ) }

    parse_config_keys(@config)

    Zlog.debug "configuration: #{@config.inspect}"
  end

  def parse( args )
    opts = {}
    rest = args

    # match arguments via block
    # anything that matches can be transformed
    # returns [ matched/transformed, unmatched ]
    def getArgs(args, &f)
      all = Array(args).map{|a|
        r = f.call(a)
        (r.nil?) ? [nil,a] : [r,nil]
      }
      [ all.map{|i|i[0]}.compact,
        all.map{|i|i[1]}.compact ]
    end

    @config['controls'].each do |k,v|
      opts[k], rest = getArgs(rest){ |c|
        m = v.match(c.downcase)
        m == nil ? nil : m
      }
    end

    opts["files"] = rest.map{ |c|
      cf = File.expand_path(c)
      File.exists?( cf ) ? cf : (
        Zlog.warning "can't find file '#{c}'"
        nil
        )
    }.compact

    opts["files"] = ["."] if opts["files"].empty? and rest.empty?

    opts
  end

  private

  # merges hash a into b
  # properly handles sub-hashes and merges them as well
  def deep_merge( a, b )
    a.each do |k,v|
      if ( v.is_a?(Hash) )
        b[k] ||= {}
        deep_merge( v, b[k] )
      else
        b[k] = v
      end
    end
  end

  # turn strings into whatever function they should perform
  # ie: "[0-9]s" => regex /[0-9]s/
  def parse_config_keys( c )
    c["controls"].each do |k,v|
      c["controls"][k] = Regexp.new(v)
    end
  end
end