require 'test/unit'
require 'minitest/spec'
require 'dynflow'

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
      return expected
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

  def finalize(outputs)
    self.class.save_recorded_outputs(outputs)
  end

end

class BusTestCase < Test::Unit::TestCase

  def setup
    @expected_scenario = []
  end

  def expect_action(action)
    @expected_scenario << action
  end

  def assert_scenario
    Dynflow::Bus.impl = TestBus.new(@expected_scenario)
    event_outputs = nil
    TestScenarioFinalizer.init_recorded_outputs
    execution_plan = self.execution_plan
    execution_plan << TestScenarioFinalizer.new({})
    Dynflow::Bus.trigger(execution_plan)
    return TestScenarioFinalizer.recorded_outputs
  end
end

class ParticipantTestCase < Test::Unit::TestCase

  def run_action(action)
    Dynflow::Bus.impl = Dynflow::Bus.new
    output = Dynflow::Bus.process(action)
    return output
  end
end
