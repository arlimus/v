#!/usr/bin/env ruby

require 'parseconfig'
require 'zlog'

class ArgumentParser
  def initialize( files = [] )
    default_configs = [ "v.default.conf" ]
    @config = {}

    ( default_configs + files ).map do |f|
      Zlog.debug "load config from '#{f}'"
      ParseConfig::new(f)
    end.each{|cur| deep_merge( cur.params, @config ) }

    Zlog.info "config: #{@config.inspect}"
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
end