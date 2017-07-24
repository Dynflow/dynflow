#!/usr/bin/env ruby
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

class SubPlansExample < Dynflow::Action
  include Dynflow::Action::WithSubPlans
  include Dynflow::Action::WithBulkSubPlans

  def create_sub_plans
    current_batch.map { |i| trigger(OrchestrateEvented::CreateMachine, "host-#{i}", 'web_server') }
  end

  def batch_size
    5
  end

  def batch(from, size)
    COUNT.times.drop(from).take(size)
  end
  
  def total_count
    COUNT
  end
end

class PollingSubPlansExample < SubPlansExample
  include Dynflow::Action::WithPollingSubPlans
end

if $0 == __FILE__
  ExampleHelper.world.action_logger.level = Logger::INFO
  ExampleHelper.world
  t1 = ExampleHelper.world.trigger(SubPlansExample)
  t2 = ExampleHelper.world.trigger(PollingSubPlansExample)
  puts example_description
  puts <<-MSG.gsub(/^.*\|/, '')
    |  Execution plans #{t1.id} and #{t2.id} with sub plans triggered
    |  You can see the details at
    |    http://localhost:4567/#{t2.id}
    |    http://localhost:4567/#{t1.id}
  MSG

  ExampleHelper.run_web_console
end
