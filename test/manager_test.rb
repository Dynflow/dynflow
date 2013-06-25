require 'test_helper'


class SimpleManagerTest < MiniTest::Unit::TestCase

  def test_simple_action
    manager = Dynflow::Manager.new({})
    plan = manager.trigger(SimpleAction, 'foo')
    assert_equal 'foo', plan.steps.last.output['id']
    assert_equal 'success', plan.steps.last.status
    assert_equal 'success', plan.status
  end


  def test_error
    manager = Dynflow::Manager.new({})
    plan = manager.trigger(ErrorAction, 'foo')
    assert_equal 'error', plan.steps.last.status
    assert_equal 'error', plan.status
  end

end
