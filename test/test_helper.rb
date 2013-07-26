require 'test/unit'
require 'minitest/spec'
if ENV['RM_INFO']
  require 'minitest/reporters'
  MiniTest::Reporters.use!
end
require 'dynflow'
require 'pry'

module PlanAssertions

  def inspect_flow(out, execution_plan, flow, prefix)
    flow
    case flow
    when Dynflow::Flows::Atom
      out << prefix
      out << flow.step.id.to_s << ': '
      out << flow.step.action_class.to_s[/\w+\Z/]
      out << "(#{flow.step.state})"
      out << ' '
      action_data = execution_plan.world.persistence_adapter.load_action(execution_plan.id, flow.step.action_id)
      out << action_data[:input].inspect
      if (output = action_data[:output])
        out << ' --> '
        out << output.inspect
      end
      out << "\n"
    else
      out << prefix << flow.class.name << "\n"
      flow.sub_flows.each do |sub_flow|
        inspect_flow(out, execution_plan, sub_flow, prefix + "  ")
      end
    end
  end

  def assert_run_flow(expected, execution_plan)
    plan_string = ""
    inspect_flow(plan_string, execution_plan, execution_plan.run_flow, "")
    plan_string.chomp.must_equal expected.chomp
  end

  def dedent(string)
    dedent = string.scan(/^ */).map { |spaces| spaces.size }.min
    string.lines.map { |line| line[dedent..-1] }.join
  end

end
