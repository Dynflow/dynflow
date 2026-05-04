#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'example_helper'

class ExampleActor
  def initialize
    @value = 0
  end

  def increment
    @value += 1
    STDOUT.puts "Value incremented to #{@value}"
  end
end

def server_world
  ExampleHelper.create_world do |config|
    config.persistence_adapter = persistence_adapter
    config.connector           = connector
    config.managed_actors.add('example', class: ExampleActor)
  end
end

def client_world
  ExampleHelper.create_world do |config|
    config.persistence_adapter = persistence_adapter
    config.connector           = connector
  end
end

def db_path
  File.expand_path('actor_remote_executor_db.sqlite', __dir__)
end

def persistence_conn_string
  ENV['DB_CONN_STRING'] || "sqlite://#{db_path}"
end

def persistence_adapter
  Dynflow::PersistenceAdapters::Sequel.new persistence_conn_string
end

def connector
  proc { |world| Dynflow::Connectors::Database.new(world) }
end

command = ARGV.first || 'server'

if $PROGRAM_NAME == __FILE__
  case command
  when 'server'
    puts <<~MSG
      The server is starting…. You can send the work to it by running:

         #{$PROGRAM_NAME} client

    MSG

    world = server_world
    world.managed_actors['example'].tell(:increment)
    ExampleHelper.run_web_console(world)
  when 'client'
    world = client_world
    100.times do |i|
      world.message_actor('example', 'increment', [])
    end
  else
    puts "Unknown command #{command}"
    exit 1
  end
end
