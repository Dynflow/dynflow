require 'test_helper'
require 'set'

module Dynflow
  module BusTest
    describe "bus" do

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

        def plan(input)
          raise 'Simulate error in plan phase' if input['name'] == 'fail_in_plan'
          plan_self(input)
        end

        def run
          raise 'Simulate error in execution phase' if input['name'] == 'fail_in_run'
          output['id'] = input['name']
        end

        def finalize(outputs)
          raise 'Simulate error in finalize phase' if input['name'] == 'fail_in_finalize'
        end

      end

      it 'returns the execution plan obejct when triggering an action' do
        Promotion.trigger(['sucess'], []).must_be_instance_of Dynflow::ExecutionPlan
      end

      describe 'handling errros in plan phase' do

        let(:failed_plan)   { Promotion.trigger(['fail_in_plan'], []) }
        let(:failed_step) { failed_plan.plan_steps.last }

        it 'marks the process as error' do
          failed_plan.status.must_equal 'error'
        end

        it 'saves errors of actions' do
          failed_step.status.must_equal "error"
          expected_error = {
            'exception' => 'RuntimeError',
            'message'   => 'Simulate error in plan phase'
          }
          failed_step.error.must_equal expected_error
        end

      end

      describe 'handling errros in execution phase' do

        let(:failed_plan)   { Promotion.trigger(['fail_in_run'], []) }
        let(:failed_step) { failed_plan.run_steps.first }

        it 'pauses the process' do
          failed_plan.status.must_equal 'paused'
        end

        it 'saves errors of actions' do
          failed_step.status.must_equal "error"
          expected_error = {
            'exception' => 'RuntimeError',
            'message'   => 'Simulate error in execution phase'
          }
          failed_step.error.must_equal expected_error
        end

        it 'allows skipping the step' do
          Dynflow::Bus.skip(failed_step)
          Dynflow::Bus.resume(failed_plan)

          failed_plan.status.must_equal 'finished'
          failed_step.status.must_equal 'skipped'
        end

        it 'allows rerunning the step' do
          failed_step.input['name'] = 'succeed'
          Dynflow::Bus.resume(failed_plan)

          failed_plan.status.must_equal 'finished'
          failed_step.output.must_equal('id' => 'succeed')
        end

      end

      describe 'handling errors in finalizatoin phase' do

        let(:failed_plan)   { Promotion.trigger(['fail_in_finalize'], []) }
        let(:failed_step) { failed_plan.finalize_steps.first }

        it 'pauses the process' do
          failed_plan.status.must_equal 'paused'
        end

        it 'saves errors of actions' do
          expected_error = {
            'exception' => 'RuntimeError',
            'message'   => 'Simulate error in finalize phase'
          }
          failed_step.error.must_equal expected_error
        end

        it 'allows finishing a finalize phase' do
          failed_step.input['name'] = 'succeed'
          Dynflow::Bus.resume(failed_plan)

          failed_plan.status.must_equal 'finished'
        end

        it 'allows skipping the step' do
          Dynflow::Bus.skip(failed_step)
          Dynflow::Bus.resume(failed_plan)

          failed_plan.status.must_equal 'finished'
          failed_step.status.must_equal 'skipped'
        end

      end

    end
  end
end
