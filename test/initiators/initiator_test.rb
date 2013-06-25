require 'test_helper'


class TestInitiator < MiniTest::Unit::TestCase

  def setup
    @plan = Dynflow::ExecutionPlan::Sequence.new
    @initiator = Dynflow::Initiators::Initiator.new
  end

  def test_start
    assert @initiator.start(@plan)
  end

end
