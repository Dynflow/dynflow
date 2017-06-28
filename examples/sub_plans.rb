#!/usr/bin/env ruby
require 'benchmark'
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

COUNT = 100

class Miniaction < Dynflow::Action
  def run; end
end

class SubPlansExample < Dynflow::Action
  include Dynflow::Action::WithSubPlans
  def create_sub_plans
    COUNT.times.map { |i| trigger(Miniaction) }
  end
end

class PollingSubPlansExample < Dynflow::Action
  include Dynflow::Action::WithSubPlans
  include Dynflow::Action::WithPollingSubPlans
  def create_sub_plans
    COUNT.times.map { |i| trigger(Miniaction) }
  end
end


if $0 == __FILE__
  Benchmark.bm do |bm|
    bm.report("evented") do
      ExampleHelper.world.trigger(SubPlansExample).finished.wait
    end
    bm.report("polling") do
      ExampleHelper.world.trigger(PollingSubPlansExample).finished.wait
    end
  end
  # puts example_description
  # puts <<-MSG.gsub(/^.*\|/, '')
  #   |  Execution plan #{triggered.id} with sub plans triggered
  #   |  You can see the details at http://localhost:4567/#{triggered.id}
  # MSG

  # ExampleHelper.run_web_console
end
