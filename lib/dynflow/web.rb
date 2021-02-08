# frozen_string_literal: true
require 'dynflow'
require 'pp'
require 'sinatra/base'
require 'yaml'

module Dynflow
  module Web

    def self.setup(&block)
      console = Sinatra.new(Web::Console) { instance_exec(&block)}
      Rack::Builder.app do
        run Rack::URLMap.new('/'        => console)
      end
    end

    def self.web_dir(sub_dir)
      web_dir = File.join(File.expand_path('../../../web', __FILE__))
      File.join(web_dir, sub_dir)
    end
  end
end
