#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require_relative 'example_helper'
require_relative 'orchestrate_evented'
require 'tmpdir'


require 'sidekiq'
require 'active_job'

ActiveJob::Base.queue_adapter = :sidekiq

class ExampleJob < ActiveJob::Base
  queue_as :default

  def perform(*args)
    puts "hello"
  end
end

class CoordinatorJob < ActiveJob::Base
  queue_as :coordinator

  def perform(*args)
    puts "hello"
  end
end

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
      ExampleHelper.run_web_console(world)
    end

    def initialize_orchestrator
      world = ExampleHelper.create_world do |config|
        config.persistence_adapter = persistence_adapter
        config.connector           = connector
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
      Proc.new { |world| Dynflow::Connectors::ActiveJob.new(world) }
    end

    def run_client
      while true do
        puts "running"
        # ExampleJob.perform_later
        CoordinatorJob.perform_later
        sleep 0.5
      end
      # world = ExampleHelper.create_world do |config|
      #   config.persistence_adapter = persistence_adapter
      #   config.executor            = false
      #   config.connector           = connector
      # end

      # world.trigger(OrchestrateEvented::CreateInfrastructure)
      # world.trigger(OrchestrateEvented::CreateInfrastructure, true)

      # loop do
      #   world.trigger(SampleAction).finished.wait
      #   sleep 0.5
      # end
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
Run active job implementation instead, such as:

sidekiq -r ./examples/remote_executor.rb -C ./examples/sidekiq.yml -q coordinator
MSG
    # RemoteExecutorExample.run_server
    # TODO AJ: remove this - use sidekiq runner instead
    exit 1
  when 'client'
    RemoteExecutorExample.run_client
  else
    puts "Unknown command #{comment}"
    exit 1
  end
else
  # assuming the remote executor was required as part of initialization
  # of the ActiveJob worker
  if Sidekiq.options[:queues].include?("dynflow_orchestrator")
    RemoteExecutorExample.initialize_orchestrator
  end
end
