require 'test/unit'
require 'minitest/spec'
if ENV['RM_INFO']
  require 'minitest/reporters'
  MiniTest::Reporters.use!
end
require 'dynflow'
require 'pry'

module PlanAssertions

  def inspect_flow(execution_plan, flow)
    out = ""
    inspect_subflow(out, execution_plan, execution_plan.run_flow, "")
    out
  end

  def inspect_plan_steps(execution_plan)
    out = ""
    inspect_plan_step(out, execution_plan, execution_plan.root_plan_step, "")
    out
  end

  def assert_run_flow(expected, execution_plan)
    inspect_flow(execution_plan, execution_plan.run_flow).chomp.must_equal dedent(expected).chomp
  end

  def assert_run_flow_equal(expected_plan, execution_plan)
    expected = inspect_flow(expected_plan, expected_plan.run_flow)
    current = inspect_flow(execution_plan, execution_plan.run_flow)
    assert_equal expected, current
  end

  def assert_plan_steps_equal(expected_plan, execution_plan)
    execution_plan.plan_steps.keys.must_equal expected_plan.plan_steps.keys

    execution_plan.plan_steps.each do |id, step|
      expected_step = expected_plan.plan_steps[id]

      step.state.must_equal expected_step.state
      step.action_class.must_equal expected_step.action_class
      step.action_id.must_equal expected_step.action_id
    end

    expected_tree = inspect_plan_steps(expected_plan)
    current_tree = inspect_plan_steps(execution_plan)
    assert_equal expected_tree, current_tree
  end

  def assert_plan_steps(expected, execution_plan)
    inspect_plan_steps(execution_plan).chomp.must_equal dedent(expected).chomp
  end

  def inspect_subflow(out, execution_plan, flow, prefix)
    case flow
    when Dynflow::Flows::Atom
      out << prefix
      out << flow.step_id.to_s << ': '
      step = execution_plan.run_steps[flow.step_id]
      out << step.action_class.to_s[/\w+\Z/]
      out << "(#{step.state})"
      out << ' '
      action = execution_plan.world.persistence.load_action(step)
      out << action.input.inspect
      unless step.state == :pending
        out << ' --> '
        out << action.output.inspect
      end
      out << "\n"
    else
      out << prefix << flow.class.name << "\n"
      flow.sub_flows.each do |sub_flow|
        inspect_subflow(out, execution_plan, sub_flow, prefix + "  ")
      end
    end
    out
  end

  def inspect_plan_step(out, execution_plan, plan_step, prefix)
    out << prefix
    out << plan_step.action_class.to_s[/\w+\Z/]
    out << "\n"
    plan_step.children.each do |sub_step_id|
      sub_step = execution_plan.plan_steps[sub_step_id]
      inspect_plan_step(out, execution_plan, sub_step, prefix + "  ")
    end
    out
  end

  include Dynflow::Dedent

end
