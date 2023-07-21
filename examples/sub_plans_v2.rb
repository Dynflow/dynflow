#!/usr/bin/env ruby
# frozen_string_literal: true
example_description = <<DESC
  Sub Plans Example
  ===================

  This example shows, how to trigger the execution plans from within a
  run method of some action and waing for them to finish.

  This is useful, when doing bulk actions, where having one big
  execution plan would not be effective, or in case all the data are
  not available by the time of original action planning.

DESC

require_relative 'example_helper'
require_relative 'orchestrate_evented'

COUNT = (ARGV[0] || 25).to_i

class Foo < Dynflow::Action
  def plan
    plan_self
  end

  def run(event = nil)
    case event
    when nil
      rng = Random.new
      plan_event(:ping, rng.rand(25) + 1)
      suspend
    when :ping
      # Finish
    end
  end
end

class SubPlansExample < Dynflow::Action
  include Dynflow::Action::V2::WithSubPlans

  def initiate
    limit_concurrency_level! 3
    super
  end

  def create_sub_plans
    current_batch.map { |i| trigger(Foo) }
  end

  def batch_size
    15
  end

  def batch(from, size)
    COUNT.times.drop(from).take(size)
  end

  def total_count
    COUNT
  end
end

if $0 == __FILE__
  ExampleHelper.world.action_logger.level = Logger::DEBUG
  ExampleHelper.world
  t1 = ExampleHelper.world.trigger(SubPlansExample)
  puts example_description
  puts <<-MSG.gsub(/^.*\|/, '')
    |  Execution plans #{t1.id} with sub plans triggered
    |  You can see the details at
    |    #{ExampleHelper::DYNFLOW_URL}/#{t1.id}
  MSG

  ExampleHelper.run_web_console
end
