#!/usr/bin/env ruby

require_relative 'example_helper'

class CustomPassedObject
  attr_reader :id, :name

  def initialize(id, name)
    @id = id
    @name = name
  end
end

class CustomPassedObjectSerializer < ::Dynflow::Serializers::Abstract
  def serialize(arg)
    # Serialized output can be anything that is representable as JSON: Array, Hash...
    { :id => arg.id, :name => arg.name }
  end

  def deserialize(arg)
    # Deserialized output must be an Array
    CustomPassedObject.new(arg[:id], arg[:name])
  end
end

class DelayedAction < Dynflow::Action

  def delay(delay_options, *args)
    CustomPassedObjectSerializer.new(args)
  end

  def plan(passed_object)
    plan_self :object_id => passed_object.id, :object_name => passed_object.name
  end

  def run
  end

end

if $0 == __FILE__
  ExampleHelper.world.action_logger.level = 1
  ExampleHelper.world.logger.level = 0

  past = Time.now - 200
  near_future = Time.now + 29
  future = Time.now + 180

  object = CustomPassedObject.new(1, 'CPS')

  past_plan = ExampleHelper.world.delay(DelayedAction, { :start_at => past, :start_before => past }, object)
  near_future_plan = ExampleHelper.world.delay(DelayedAction, { :start_at => near_future, :start_before => future }, object)
  future_plan = ExampleHelper.world.delay(DelayedAction, { :start_at => future }, object)

  puts <<-MSG.gsub(/^.*\|/, '')
    |
    |  Future Execution Example
    |  ========================
    |
    |  This example shows the future execution functionality of Dynflow, which allows to plan actions to be executed at set time.
    |
    |  Execution plans:
    |    #{past_plan.id} is "delayed" to execute before #{past} and should timeout on the first run of the scheduler.
    |    #{near_future_plan.id} is delayed to execute at #{near_future} and should run successfully.
    |    #{future_plan.id} is delayed to execute at #{future} and should run successfully.
    |
    |  Visit http://localhost:4567 to see their status.
    |
  MSG

  ExampleHelper.run_web_console
end
