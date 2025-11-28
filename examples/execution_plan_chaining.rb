#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'example_helper'

class DelayedAction < Dynflow::Action
  def plan(should_fail = false)
    plan_self :should_fail => should_fail
  end

  def run
    sleep 5
    raise "Controlled failure" if input[:should_fail]
  end

  def rescue_strategy
    Dynflow::Action::Rescue::Fail
  end
end

if $PROGRAM_NAME == __FILE__
  world = ExampleHelper.create_world do |config|
    config.auto_rescue = true
  end
  world.action_logger.level = 1
  world.logger.level = 0

  plan1 = world.trigger(DelayedAction)
  plan2 = world.chain(plan1.execution_plan_id, DelayedAction)
  plan3 = world.chain(plan2.execution_plan_id, DelayedAction)
  plan4 = world.chain(plan2.execution_plan_id, DelayedAction)

  plan5 = world.trigger(DelayedAction, true)
  plan6 = world.chain(plan5.execution_plan_id, DelayedAction)

  puts <<-MSG.gsub(/^.*\|/, '')
    |
    |  Execution Plan Chaining example
    |  ========================
    |
    |  This example shows the execution plan chaining functionality of Dynflow, which allows execution plans to wait until another execution plan finishes.
    |
    |  Execution plans:
    |    #{plan1.id} runs immediately and should run successfully.
    |    #{plan2.id} is delayed and should run once #{plan1.id} finishes.
    |    #{plan3.id} and #{plan4.id} are delayed and should run once #{plan2.id} finishes.
    |
    |    #{plan5.id} runs immediately and is expected to fail.
    |    #{plan6.id} should not run at all as its prerequisite failed.
    |
    |  Visit #{ExampleHelper::DYNFLOW_URL} to see their status.
    |
  MSG

  ExampleHelper.run_web_console(world)
end
