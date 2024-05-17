#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'example_helper'

class DelayedAction < Dynflow::Action
  def plan
    plan_self
  end

  def run
    sleep 5
  end
end

if $0 == __FILE__
  ExampleHelper.world.action_logger.level = 1
  ExampleHelper.world.logger.level = 0

  plan1 = ExampleHelper.world.trigger(DelayedAction)
  plan2 = ExampleHelper.world.chain(plan1.execution_plan_id, DelayedAction)
  plan3 = ExampleHelper.world.chain(plan2.execution_plan_id, DelayedAction)
  plan4 = ExampleHelper.world.chain(plan2.execution_plan_id, DelayedAction)

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
    |  Visit #{ExampleHelper::DYNFLOW_URL} to see their status.
    |
  MSG

  ExampleHelper.run_web_console
end
