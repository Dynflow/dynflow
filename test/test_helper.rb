require 'test/unit'
require 'minitest/spec'
require 'eventum'

BUS_IMPL = Eventum::Bus::MemoryBus

class TestBus < BUS_IMPL

  def initialize(expected_scenario)
    super()
    @expected_scenario = expected_scenario
  end

  def process(action_class, input, output = nil, stub = true)
    expected = @expected_scenario.shift
    if action_class == TestScenarioFinalizer || !stub || output
      return super(action_class, input, output)
    elsif action_class.name == expected[:action_class].name && input == expected[:input]
      return action_class.new(expected[:input], expected[:output])
    else
      raise "Unexpected input. Expected #{expected[:action_class]} #{expected[:input].inspect}, got #{action_class} #{input.inspect}"
    end
  end

end

class TestScenarioFinalizer < Eventum::Action

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

  def expect_input(action_class, input, output)
    @expected_scenario << {
      :action_class => action_class,
      :input => input,
      :output => output
    }
  end

  def assert_scenario
    Eventum::Bus.impl = TestBus.new(@expected_scenario)
    event_outputs = nil
    TestScenarioFinalizer.init_recorded_outputs
    execution_plan = self.execution_plan
    execution_plan << [TestScenarioFinalizer, {}]
    Eventum::Bus.trigger(execution_plan)
    return TestScenarioFinalizer.recorded_outputs
  end
end

class ParticipantTestCase < Test::Unit::TestCase

  def run_action(action_class, input)
    Eventum::Bus.impl = Eventum::Bus.new
    output = Eventum::Bus.process(action_class, input)
    return output
  end
end
