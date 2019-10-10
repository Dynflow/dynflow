#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# frozen_string_literal: true

# To run the observer:
#
#      bundle exec ruby ./examples/remote_executor.rb observer
#
# To run the server:
#
#      bundle exec ruby ./examples/remote_executor.rb server
#
# To run the client:
#
#      bundle exec ruby ./examples/remote_executor.rb client
#
# Sidekiq
# =======
#
# In case of using Sidekiq as async job backend, use this instead of the server command
#
# To run the orchestrator:
#
#      bundle exec sidekiq -r ./examples/remote_executor.rb -q dynflow_orchestrator
#
# To run the worker:
#
#      bundle exec sidekiq -r ./examples/remote_executor.rb -q default

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
        config.executor            = ::Dynflow::Executors::Sidekiq::Core
        config.auto_validity_check = false
      end
    end

    def initialize_sidekiq_worker
      Sidekiq.configure_server do |config|
        require 'sidekiq-reliable-fetch'
        # Use semi-reliable fetch
        # for details see https://gitlab.com/gitlab-org/sidekiq-reliable-fetch/blob/master/README.md
        config.options[:semi_reliable_fetch] = true
        Sidekiq::ReliableFetch.setup_reliable_fetch!(config)
      end
      ExampleHelper.create_world do |config|
        config.persistence_adapter = persistence_adapter
        config.connector           = connector
        config.executor            = false
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
        start_time = Time.now
        world.trigger(SampleAction).finished.wait
        finished_in = Time.now - start_time
        puts "Finished in #{finished_in}s"
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
  world = if Sidekiq.options[:queues].include?("dynflow_orchestrator")
    RemoteExecutorExample.initialize_sidekiq_orchestrator
  elsif (Sidekiq.options[:queues] - ['dynflow_orchestrator']).any?
    RemoteExecutorExample.initialize_sidekiq_worker
  end
  Sidekiq.options[:dynflow_world] = world
end
