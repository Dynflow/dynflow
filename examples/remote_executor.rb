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
      world               = ExampleHelper.create_world(persistence_adapter: persistence_adapter)
      listener            = Dynflow::Listeners::Socket.new world, socket

      Thread.new { Dynflow::Daemon.new(listener, world).run }
      ExampleHelper.run_web_console(world)
    ensure
      File.delete(db_path)
    end

    def run_client
      executor = ->(world) { Dynflow::Executors::RemoteViaSocket.new(world, socket) }
      world    = ExampleHelper.create_world(persistence_adapter: persistence_adapter,
                                            executor:            executor)

      loop do
        world.trigger(SampleAction).finished.wait
        sleep 0.5
      end
    end

    def socket
      File.join(Dir.tmpdir, 'dynflow_socket')
    end

    def persistence_adapter
      Dynflow::PersistenceAdapters::Sequel.new "sqlite://#{db_path}"
    end

    def db_path
      File.expand_path("../remote_executor_db.sqlite", __FILE__)
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
