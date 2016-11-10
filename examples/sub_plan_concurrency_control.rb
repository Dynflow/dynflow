#!/usr/bin/env ruby

example_description = <<DESC
  Sub-plan Concurrency Control Example
  ====================================

  This example shows, how an action with sub-plans can be used
  to control concurrency level and tasks distribution over time.

  This is useful, when doing resource-intensive bulk actions,
  where running all actions at once would drain the system's resources.

DESC

require_relative 'example_helper'

class CostyAction < Dynflow::Action

  SleepTime = 10

  def plan(number)
    action_logger.info("#{number} PLAN")
    plan_self(:number => number)
  end

  def run(event = nil)
    unless output.key? :slept
      output[:slept] = true
      suspend do |suspended_action|
        action_logger.info("#{input[:number]} SLEEP")
        world.clock.ping(suspended_action, SleepTime)
      end
    end
  end

  def finalize
    action_logger.info("#{input[:number]} DONE")
  end
end

class ConcurrencyControlExample < Dynflow::Action
  include Dynflow::Action::WithSubPlans

  ConcurrencyLevel = 2
  RunWithin = 2 * 60

  def plan(count)
    limit_concurrency_level(ConcurrencyLevel)
    distribute_over_time(RunWithin)
    super(:count => count)
  end

  def create_sub_plans
    sleep 1
    input[:count].times.map { |i| trigger(CostyAction, i) }
  end
end

if $0 == __FILE__
  ExampleHelper.world.action_logger.level = Logger::INFO
  triggered = ExampleHelper.world.trigger(ConcurrencyControlExample, 10)
  puts example_description
  puts <<-MSG.gsub(/^.*\|/, '')
    |  Execution plan #{triggered.id} with 10 sub plans triggered
    |  You can see the details at http://localhost:4567/#{triggered.id}/actions/1/sub_plans
    |  Or simply watch in the console that there are never more than #{ConcurrencyControlExample::ConcurrencyLevel} running at the same time.
    |
    |  The tasks are distributed over #{ConcurrencyControlExample::RunWithin} seconds.
  MSG

  ExampleHelper.run_web_console
end
