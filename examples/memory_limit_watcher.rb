#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'example_helper'

example_description = <<DESC
  Memory limit watcher Example
  ===========================

In this example we are setting a watcher that will terminate our world object
when process memory consumption exceeds a limit that will be set.


DESC

module MemorylimiterExample
  class SampleAction < Dynflow::Action
    def plan(memory_to_use)
      plan_self(number: memory_to_use)
    end

    def run
      array = Array.new(input[:number].to_i)
      puts "[action] allocated #{input[:number]} cells"
    end
  end
end

if $0 == __FILE__
  puts example_description

  world = ExampleHelper.create_world do |config|
    config.exit_on_terminate = false
  end

  world.terminated.on_resolution do
    puts '[world] The world has been terminated'
  end

  require 'get_process_mem'
  memory_info_provider = GetProcessMem.new
  puts '[info] Preparing memory watcher: '
  require 'dynflow/watchers/memory_consumption_watcher'
  puts "[info] now the process consumes #{memory_info_provider.bytes} bytes."
  limit = memory_info_provider.bytes + 500_000
  puts "[info] Setting memory limit to #{limit} bytes"
  watcher = Dynflow::Watchers::MemoryConsumptionWatcher.new(world, limit, polling_interval: 1)
  puts '[info] Small action: '
  world.trigger(MemorylimiterExample::SampleAction, 10)
  sleep 2
  puts "[info] now the process consumes #{memory_info_provider.bytes} bytes."
  puts '[info] Big action: '
  world.trigger(MemorylimiterExample::SampleAction, 500_000)
  sleep 2
  puts "[info] now the process consumes #{memory_info_provider.bytes} bytes."
  puts '[info] Small action again - will not execute, the world is not accepting requests'
  world.trigger(MemorylimiterExample::SampleAction, 500_000)
  sleep 2
  puts 'Done'
end
