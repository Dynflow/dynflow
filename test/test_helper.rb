require 'test/unit'
require 'minitest/spec'
require 'dynflow'
require 'pry'

BUS_IMPL = Dynflow::Bus::MemoryBus

class TestBus < BUS_IMPL

  def initialize(expected_scenario)
    super()
    @expected_scenario = expected_scenario
  end

  def process(action)
    expected = @expected_scenario.shift
    if action.class == TestScenarioFinalizer
      return super
    elsif action.class == expected.class && action.input == expected.input
      action.output = expected.output
      action.status = 'success'
      return action
    else
      raise "Unexpected input. Expected #{expected.class} #{expected.input.inspect}, got #{action.class} #{action.input.inspect}"
    end
  end

end

class TestScenarioFinalizer < Dynflow::Action

  class << self

    def recorded_outputs
      @recorded_outputs
    end

    def init_recorded_outputs
      @recorded_outputs = []
    end

    def save_recorded_outputs(recorded_outputs)
      @recorded_outputs = recorded_outputs
    end

  end

  def finalize(actions)
    self.class.save_recorded_outputs(actions)
  end

end

class MockedAction

  def initialize(mocked_execution_plan)
    @mocked_execution_plan = mocked_execution_plan
  end

  def plan
    @mocked_execution_plan
  end
end

module BusTestCase

  def setup
    @expected_scenario = []
  end

  def expect_action(action)
    @expected_scenario << action
  end

  def assert_scenario
    original_bus_impl = Dynflow::Bus.impl
    Dynflow::Bus.impl = TestBus.new(@expected_scenario)
    event_outputs = nil
    TestScenarioFinalizer.init_recorded_outputs
    execution_plan = self.execution_plan
    execution_plan << TestScenarioFinalizer.new({})

    Dynflow::Bus.trigger(MockedAction.new(execution_plan))
    return TestScenarioFinalizer.recorded_outputs
  ensure
    Dynflow::Bus.impl = original_bus_impl
  end
end

class ParticipantTestCase < Test::Unit::TestCase

  def run_action(action)
    Dynflow::Bus.impl = Dynflow::Bus.new
    output = Dynflow::Bus.impl.process(action)
    return output
  end
end
