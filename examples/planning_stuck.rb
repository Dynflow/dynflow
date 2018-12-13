#!/usr/bin/env ruby

require_relative 'example_helper'

class Stuck < Dynflow::Action
  def plan
    puts "Getting stuck"
    Kernel.exit!
  end
end

if $0 == __FILE__
  ExampleHelper.world.action_logger.level = 1
  ExampleHelper.world.logger.level = 0

  ExampleHelper.world.trigger(Stuck) if ARGV[0] == 'stuck'

  ExampleHelper.run_web_console
end
