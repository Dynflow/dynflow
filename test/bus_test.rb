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
      Promotion.trigger(['sucess'], []).must_be_instance_of Dynflow::ExecutionPlan
    end

    describe 'handling errros in execution phase' do

      let(:failed_plan)   { Promotion.trigger(['fail_in_run'], []) }
      let(:failed_action) { failed_plan.actions.first }

      it 'pauses the process' do
        failed_plan.status.must_equal 'paused'
      end

      it 'saves errors of actions' do
        failed_action.status.must_equal "error"
        expected_error = {
          'exception' => 'RuntimeError',
          'message'   => 'Simulate error in execution phase'
        }
        failed_action.output['error'].must_equal expected_error
      end

      it 'allows skipping an action' do
        Dynflow::Bus.impl.skip(failed_action)
        Dynflow::Bus.impl.resume(failed_plan)

        failed_plan.status.must_equal 'finished'
        failed_action.status.must_equal 'skipped'
      end

      it 'allows rerunning an action' do
        failed_action.input['name'] = 'succeed'
        Dynflow::Bus.impl.resume(failed_plan)

        failed_plan.status.must_equal 'finished'
      end

    end

    describe 'handling errors in finalizatoin phase' do

      it 'allows finishing a finalize phase'

    end

  end
end
