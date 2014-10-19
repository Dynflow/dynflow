#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require_relative 'example_helper'
require 'tmpdir'

class SampleAction < Dynflow::Action
  def plan
    number = rand(1e10)
    puts "Plannin action: #{number}"
    plan_self(number: number)
  end

  def run
    puts "Running action: #{input[:number]}"
  end
end

class RemoteExecutorExample
  class << self

    def run_server
      world               = ExampleHelper.create_world do |config|
        config.persistence_adapter = persistence_adapter
        config.connector           = connector
      end
      begin
        ExampleHelper.run_web_console(world)
      rescue Errno::EADDRINUSE
        STDIN.gets
      end
    end

    def db_path
      File.expand_path("../remote_executor_db.sqlite", __FILE__)
    end

    def persistence_conn_string
      ENV['DB_CONN_STRING'] || "sqlite://#{db_path}"
    end

    def persistence_adapter
      Dynflow::PersistenceAdapters::Sequel.new persistence_conn_string
    end

    def connector
      Proc.new { |world| Dynflow::Connectors::Database.new(world) }
    end

    def run_client
      world    = ExampleHelper.create_world do |config|
        config.persistence_adapter = persistence_adapter
        config.executor            = false
        config.connector           = connector
      end

      loop do
        world.trigger(SampleAction).finished.wait
        sleep 0.5
      end
    end

  end
end

command = ARGV.first || 'server'

if $0 == __FILE__
  case command
  when 'server'
    puts <<MSG
The server is starting…. You can send the work to it by running:

   #{$0} client

MSG
   RemoteExecutorExample.run_server
  when 'client'
    RemoteExecutorExample.run_client
  else
    puts "Unknown command #{comment}"
    exit 1
  end
end
