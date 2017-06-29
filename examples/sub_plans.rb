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

COUNT = ARGV[0].to_i

class Miniaction < Dynflow::Action
  def run; end
end

class Common < Dynflow::Action
  include Dynflow::Action::WithSubPlans
  include Dynflow::Action::WithBulkSubPlans

  def create_sub_plans
    current_batch.map { |i| trigger(Miniaction) }
  end

  def batch_size
    100
  end

  def batch(from, size)
    COUNT.times.drop(from).take(size)
  end
  
  def total_count
    COUNT
  end
end

class SubPlansExample < Common
end

class PollingSubPlansExample < Common
  include Dynflow::Action::WithPollingSubPlans
end


if $0 == __FILE__
  ExampleHelper.world.action_logger.level = Logger::INFO
  ExampleHelper.world
  t1 = t2 = nil
  Benchmark.bm do |bm|
    bm.report("evented") do
      t1 = ExampleHelper.world.trigger(SubPlansExample)
      t1.finished.wait
    end
    bm.report("polling") do
      t2 = ExampleHelper.world.trigger(PollingSubPlansExample)
      t2.finished.wait
    end
  end
  # puts example_description
  # puts <<-MSG.gsub(/^.*\|/, '')
  #   |  Execution plan #{triggered.id} with sub plans triggered
  #   |  You can see the details at http://localhost:4567/#{triggered.id}
  # MSG
  puts t1.id
  puts t2.id

  ExampleHelper.run_web_console
end
