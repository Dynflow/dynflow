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

class SubPlansExample < Dynflow::Action
  include Dynflow::Action::WithSubPlans

  def create_sub_plans
    10.times.map { |i| trigger(OrchestrateEvented::CreateMachine, "host-#{i}", 'web_server') }
  end
end

if $0 == __FILE__
  triggered = ExampleHelper.world.trigger(SubPlansExample)
  puts example_description
  puts <<-MSG.gsub(/^.*\|/, '')
    |  Execution plan #{triggered.id} with sub plans triggered
    |  You can see the details at http://localhost:4567/#{triggered.id}
  MSG

  ExampleHelper.run_web_console
end
