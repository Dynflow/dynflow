require 'test/unit'
require 'minitest/spec'
require 'minitest/reporters'
MiniTest::Reporters.use!
require 'dynflow'
require 'pry'


module PlanAssertions

  def inspect_flow(out, flow, prefix)
    case flow
    when Dynflow::Flows::Atom
      out << prefix
      out << flow.step.id.to_s << ': '
      action = flow.step.action
      out << action.class.superclass.name[/\w+\Z/]
      out << ' '
      out << action.input.inspect
      out << "\n"
    else
      out << prefix << flow.class.name << "\n"
      flow.sub_flows.each do |sub_flow|
        inspect_flow(out, sub_flow, prefix + "  ")
      end
    end
  end

  def assert_run_plan(expected, execution_plan)
    plan_string = ""
    inspect_flow(plan_string, execution_plan.run_flow, "")
    plan_string.chomp.must_equal expected.chomp
  end

end
