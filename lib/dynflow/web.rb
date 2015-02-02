require 'dynflow'
require 'pp'
require 'sinatra'
require 'yaml'

module Dynflow
  module Web

    def self.setup(&block)
      old_console = Sinatra.new(Web::LegacyConsole) { instance_exec(&block)}
      Rack::Builder.app do
        run Rack::URLMap.new('/'        => old_console)
      end
    end

    def self.web_dir(sub_dir)
      web_dir = File.join(File.expand_path('../../../web', __FILE__))
      File.join(web_dir, sub_dir)
    end

    require 'dynflow/web/filtering_helpers'
    require 'dynflow/web/world_helpers'
    require 'dynflow/web/legacy_helpers'
    require 'dynflow/web/legacy_console'
  end
end
