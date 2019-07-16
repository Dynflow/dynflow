#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# For using sidekiq as the worker infrastructure:
#
# To run the orchestrator:
#
#      bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
#
# To run the worker:
#
#      bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
#
# To run the observer:
#
#      bundle exec ruby ./examples/remote_executor.rb observer
#
#  TODO: info about sidekiq console
#
# To run the client:
#
#      bundle exec ruby ./examples/remote_executor.rb client

require_relative 'example_helper'
require_relative 'orchestrate_evented'
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

    def run_observer
      world = ExampleHelper.create_world do |config|
        config.persistence_adapter = persistence_adapter
        config.connector           = connector
        config.executor            = false
      end
      run(world)
    end

    def run_server
      world = ExampleHelper.create_world do |config|
        config.persistence_adapter = persistence_adapter
        config.connector           = connector
      end
      run(world)
    end

    def initialize_sidekiq_orchestrator
      ExampleHelper.create_world do |config|
        config.persistence_adapter = persistence_adapter
        config.connector           = connector
        config.process_role        = :orchestrator
      end
    end

    def initialize_sidekiq_worker
      ExampleHelper.create_world do |config|
        config.persistence_adapter = persistence_adapter
        config.connector           = connector
        config.executor            = false
        config.process_role        = :worker
      end
    end

    def run(world)
      begin
        ExampleHelper.run_web_console(world)
      rescue Errno::EADDRINUSE
        require 'io/console'
        puts "Running without a web console. Press q<enter> to quit."
        until STDIN.gets.chomp == 'q'
        end
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
      world = ExampleHelper.create_world do |config|
        config.persistence_adapter = persistence_adapter
        config.executor            = false
        config.connector           = connector
      end

      world.trigger(OrchestrateEvented::CreateInfrastructure)
      world.trigger(OrchestrateEvented::CreateInfrastructure, true)

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
  when 'observer'
    puts <<MSG
The observer starting…. You can see what's going on there
MSG
    RemoteExecutorExample.run_observer
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
elsif defined?(Sidekiq)
  # TODO:
  Sidekiq.default_worker_options = { :retry => 0, 'backtrace' => true }
  # assuming the remote executor was required as part of initialization
  # of the ActiveJob worker
  if Sidekiq.options[:queues].include?("dynflow_orchestrator")
    RemoteExecutorExample.initialize_sidekiq_orchestrator
  elsif (Sidekiq.options[:queues] - ['dynflow_orchestrator']).any?
    RemoteExecutorExample.initialize_sidekiq_worker
  end
end
