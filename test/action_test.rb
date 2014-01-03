require_relative 'test_helper'
require_relative 'code_workflow_example'

module Dynflow


  describe Action::Missing do
    include WorldInstance

    let :action_data do
      { class:             'RenamedAction',
        id:                123,
        input:             {},
        execution_plan_id: 123 }
    end

    subject do
      state_holder = ExecutionPlan::Steps::Abstract.allocate
      state_holder.set_state :success, true
      Action.from_hash(action_data, :run_phase, state_holder, world)
    end

    specify { subject.action_class.name.must_equal 'RenamedAction' }
    specify { assert subject.is_a? Action }
  end

  describe "extending action phase" do

    module TestExtending

      module Extension
        def new_method
        end
      end

      class ExtendedAction < Dynflow::Action
        def self.phase_modules
          super.merge(run_phase: [Extension]) { |key, old, new| old + new }.freeze
        end
      end
    end

    it "is possible to extend the action just for some phase" do
      refute TestExtending::ExtendedAction.plan_phase.instance_methods.include?(:new_method)
      refute Dynflow::Action.run_phase.instance_methods.include?(:new_method)
      assert TestExtending::ExtendedAction.run_phase.instance_methods.include?(:new_method)
    end
  end


  describe 'children' do
    include WorldInstance

    smart_action_class   = Class.new(Dynflow::Action)
    smarter_action_class = Class.new(smart_action_class)

    specify { refute smart_action_class.phase? }
    specify { refute smarter_action_class.phase? }
    specify { assert smarter_action_class.plan_phase.phase? }

    specify { smart_action_class.all_children.must_include smarter_action_class }
    specify { smart_action_class.all_children.size.must_equal 1 }
    specify { smart_action_class.all_children.wont_include smarter_action_class.plan_phase }
    specify { smart_action_class.all_children.wont_include smarter_action_class.run_phase }
    specify { smart_action_class.all_children.wont_include smarter_action_class.finalize_phase }

    describe 'World#subscribed_actions' do
      event_action_class      = CodeWorkflowExample::Triage
      subscribed_action_class = CodeWorkflowExample::NotifyAssignee

      specify { subscribed_action_class.subscribe.must_equal event_action_class }
      specify { world.subscribed_actions(event_action_class).must_include subscribed_action_class }
      specify { world.subscribed_actions(event_action_class).size.must_equal 1 }
    end
  end

  describe Action::Presenter do
    include WorldInstance

    let :execution_plan do
      id, planned, finished = *world.trigger(CodeWorkflowExample::IncomingIssues, issues_data)
      raise unless planned
      finished.value
    end

    let :issues_data do
      [{ 'author' => 'Peter Smith', 'text' => 'Failing test' },
       { 'author' => 'John Doe', 'text' => 'Internal server error' }]
    end

    let :presenter do
      execution_plan.actions.find do |action|
        action.is_a? CodeWorkflowExample::IncomingIssues
      end
    end

    specify { presenter.action_class.must_equal CodeWorkflowExample::IncomingIssues }

    it 'allows aggregating data from other actions' do
      presenter.summary.must_equal(assignees: ["John Doe"])
    end
  end
end
