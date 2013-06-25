require 'test_helper'


class TestWorker < MiniTest::Unit::TestCase

  def setup
    @step_mock = Minitest::Mock.new
    @step_mock.expect(:prepare, true)
    @step_mock.expect(:run, true)
    @step_mock.expect(:persist_after_run, true)
    @step_mock.expect(:status, true)

    @worker = Dynflow::Worker.new
  end

  def test_mock_responds
    step = Dynflow::RunStep.new(:action_class => Object)
    step.must_respond_to(:prepare)
    step.must_respond_to(:run)
    step.must_respond_to(:persist_after_run)
    step.must_respond_to(:status)
  end

  def test_run
    assert @worker.run(@step_mock)
    @step_mock.verify
  end

end
