#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'example_helper'

example_description = <<DESC

  Halting example
  ===================

  This example shows, how halting works in Dynflow. It spawns a single action,
  which in turn spawns a few evented actions and a single action which occupies
  the executor for a long time.

  Once the halt event is sent, the execution plan is halted, suspended steps
  stay suspended forever, running steps stay running until they actually finish
  the current run and the execution state is flipped over to stopped state.

  You can see the details at #{ExampleHelper::DYNFLOW_URL}

DESC

class EventedCounter < Dynflow::Action
  def run(event = nil)
    output[:counter] ||= 0
    output[:counter] += 1
    action_logger.info "Iteration #{output[:counter]}"

    if output[:counter] < input[:count]
      plan_event(:tick, 5)
      suspend
    end
    action_logger.info "Done"
  end
end

class Sleeper < Dynflow::Action
  def run
    sleep input[:time]
  end
end

class Wrapper < Dynflow::Action
  def plan
    sequence do
      concurrence do
        5.times { |i| plan_action(EventedCounter, :count => i + 1) }
        plan_action Sleeper, :time => 20
      end
      plan_self
    end
  end

  def run
    # Noop
  end
end

if $PROGRAM_NAME == __FILE__
  puts example_description

  ExampleHelper.world.action_logger.level = Logger::DEBUG
  ExampleHelper.world
  t = ExampleHelper.world.trigger(Wrapper)
  Thread.new do
    sleep 8
    ExampleHelper.world.halt(t.id)
  end

  ExampleHelper.run_web_console
end
