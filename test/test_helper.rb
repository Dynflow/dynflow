require 'test/unit'
require 'minitest/spec'
require 'minitest/reporters'
MiniTest::Reporters.use!
require 'dynflow'
require 'pry'


module PlanAssertions

  def inspect_step(out, step, prefix)
    if step.respond_to? :steps
      out << prefix << step.class.name << "\n"
      step.steps.each { |sub_step| inspect_step(out, sub_step, prefix + "  ") }
    else
      string = step.inspect.gsub(step.action_class.name.sub(/\w+\Z/,''),'')
      out << prefix << string << "\n"
    end
  end

  def assert_run_plan(expected, execution_plan)
    plan_string = ""
    inspect_step(plan_string, execution_plan.run_plan, "")
    plan_string.chomp.must_equal expected.chomp
  end

end
