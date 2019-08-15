#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'example_helper'

class Sleeper < Dynflow::Action
  def run(event = nil)
    sleep
  end
end

def report(msg)
  puts "===== #{Time.now}: #{msg}"
end

if $0 == __FILE__
  ExampleHelper.world.action_logger.level = 1
  ExampleHelper.world.logger.level = 0

  ExampleHelper.world.trigger(Sleeper)
  report "Sleeping"
  sleep 5

  report "Asking to terminate"
  ExampleHelper.world.terminate.wait
  report "Terminated"
end
