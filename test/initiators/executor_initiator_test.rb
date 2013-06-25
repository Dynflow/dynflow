require 'test_helper'


class TestExecutorInitiator < MiniTest::Unit::TestCase

  def setup
    @plan = Dynflow::ExecutionPlan::Sequence.new
    @initiator = Dynflow::Initiators::ExecutorInitiator.new
  end

  def test_start
    assert @initiator.start(@plan)
  end

end
