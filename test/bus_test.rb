require 'test_helper'
require 'set'

module Dynflow
  describe "bus" do
    include BusTestCase
    class Promotion < Action

      def plan(repo_names, package_names)
        repo_names.each do |repo_name|
          plan_action(CloneRepo, {'name' => repo_name})
        end

        package_names.each do |package_name|
          plan_action(ClonePackage, {'name' => package_name})
        end
      end

    end

    class CloneRepo < Action

      input_format do
        param :name, String
      end

      output_format do
        param :id, String
      end

      def run
        raise 'Simulate error in execution phase' if input['name'] == 'fail_in_run'
        output['id'] = input['name']
      end

    end

    def execution_plan
      ExecutionPlan.new.tap do |ep|
        ep << CloneRepo.new('name' => 'zoo')
        ep << CloneRepo.new('name' => 'foo')
      end
    end

    it "performs the actions from an action's execution plan" do
      expect_action(CloneRepo.new({'name' => 'zoo'}, {'id' => '123'}))
      expect_action(CloneRepo.new({'name' => 'foo'}, {'id' => '456'}))
      first_action, second_action = assert_scenario

      assert_equal({'name' => 'zoo'}, first_action.input)
      assert_equal({'id' => '123'},   first_action.output)
      assert_equal({'name' => 'foo'}, second_action.input)
      assert_equal({'id' => '456'},   second_action.output)
    end


    it 'returns the execution plan obejct when triggering an action' do
      ret = Promotion.trigger(['zoo'], [])
      ret.must_be_instance_of Dynflow::ExecutionPlan
    end

    # the following should be generic
    it 'saves errors of actions'

    it 'allows skipping an action'

    it 'allows rerunning an action' do
      plan = Promotion.trigger(['fail_in_run'], [])
      plan.status.must_equal 'paused'

      plan.actions.first.input['name'] = 'succeed'
      Dynflow::Bus.impl.resume(plan)

      plan.status.must_equal 'finished'
    end

    it 'allows finishing a finalize phase'

  end
end
