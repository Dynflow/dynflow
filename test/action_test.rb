require_relative 'test_helper'

module Dynflow
  describe 'action' do
    include WorldInstance

    describe Action::Missing do

      let :action_data do
        { class:             'RenamedAction',
          id:                1,
          input:             {},
          output:            {},
          execution_plan_id: '123',
          plan_step_id:      2,
          run_step_id:       3,
          finalize_step_id:  nil,
          phase:             Action::Run }
      end

      subject do
        step = ExecutionPlan::Steps::Abstract.allocate
        step.set_state :success, true
        Action.from_hash(action_data.merge(step: step), world)
      end

      specify { subject.class.name.must_equal 'RenamedAction' }
      specify { assert subject.is_a? Action }
    end

    describe 'children' do

      smart_action_class   = Class.new(Dynflow::Action)
      smarter_action_class = Class.new(smart_action_class)

      specify { smart_action_class.all_children.must_include smarter_action_class }
      specify { smart_action_class.all_children.size.must_equal 1 }

      describe 'World#subscribed_actions' do
        event_action_class      = Support::CodeWorkflowExample::Triage
        subscribed_action_class = Support::CodeWorkflowExample::NotifyAssignee

        specify { subscribed_action_class.subscribe.must_equal event_action_class }
        specify { world.subscribed_actions(event_action_class).must_include subscribed_action_class }
        specify { world.subscribed_actions(event_action_class).size.must_equal 1 }
      end
    end

    describe Action::Present do
      include WorldInstance

      let :execution_plan do
        result = world.trigger(Support::CodeWorkflowExample::IncomingIssues, issues_data)
        result.must_be :planned?
        result.finished.value
      end

      let :issues_data do
        [{ 'author' => 'Peter Smith', 'text' => 'Failing test' },
         { 'author' => 'John Doe', 'text' => 'Internal server error' }]
      end

      let :presenter do
        execution_plan.root_plan_step.action execution_plan
      end

      specify { presenter.class.must_equal Support::CodeWorkflowExample::IncomingIssues }

      it 'allows aggregating data from other actions' do
        presenter.summary.must_equal(assignees: ["John Doe"])
      end
    end

    describe 'serialization' do

      include Testing

      it 'fails when input is not serializable' do
        klass = Class.new(Dynflow::Action)
        -> { create_and_plan_action klass, key: Object.new }.must_raise NoMethodError
      end

      it 'fails when output is not serializable' do
        klass  = Class.new(Dynflow::Action) do
          def run
            output.update key: Object.new
          end
        end
        action = create_and_plan_action klass, {}
        -> { run_action action }.must_raise NoMethodError
      end
    end

  end
end
