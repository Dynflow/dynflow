require_relative 'test_helper'

module Dynflow
  describe 'action' do

    let(:world) { WorldFactory.create_world }

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

    describe 'polling action' do
      CWE = Support::CodeWorkflowExample
      include Dynflow::Testing

      class ExternalService
        def invoke(args)
          reset!
        end

        def poll(id)
          raise 'fail' if @current_state[:failing]
          @current_state[:progress] += 10
          return @current_state
        end

        def reset!
          @current_state = { task_id: 123, progress: 0 }
        end

        def will_fail
          @current_state[:failing] = true
        end

        def wont_fail
          @current_state.delete(:failing)
        end
      end

      class TestPollingAction < Dynflow::Action

        class Config
          attr_accessor :external_service, :poll_max_retries,
              :poll_intervals, :attempts_before_next_interval

          def initialize
            @external_service              = ExternalService.new
            @poll_max_retries              = 2
            @poll_intervals                = [0.5, 1]
            @attempts_before_next_interval = 2
          end
        end

        include Dynflow::Action::Polling

        def invoke_external_task
          external_service.invoke(input[:task_args])
        end

        def poll_external_task
          external_service.poll(external_task[:task_id])
        end

        def done?
          external_task && external_task[:progress] >= 100
        end

        def poll_max_retries
          self.class.config.poll_max_retries
        end

        def poll_intervals
          self.class.config.poll_intervals
        end

        def attempts_before_next_interval
          self.class.config.attempts_before_next_interval
        end

        class << self
          def config
            @config ||= Config.new
          end

          attr_writer :config
        end

        def external_service
          self.class.config.external_service
        end
      end

      let(:plan) do
        create_and_plan_action TestPollingAction, { task_args: 'do something' }
      end

      before do
        TestPollingAction.config = TestPollingAction::Config.new
      end

      def next_ping(action)
        action.world.clock.pending_pings.first
      end

      it 'initiates the external task' do
        action   = run_action plan

        action.output[:task][:task_id].must_equal 123
      end

      it 'polls till the task is done' do
        action   = run_action plan

        9.times { progress_action_time action }
        action.done?.must_equal false
        next_ping(action).wont_be_nil
        action.state.must_equal :suspended

        progress_action_time action
        action.done?.must_equal true
        next_ping(action).must_be_nil
        action.state.must_equal :success
      end

      it 'tries to poll for the old task when resuming' do
        action   = run_action plan
        action.output[:task][:progress].must_equal 0
        run_action action
        action.output[:task][:progress].must_equal 10
      end

      it 'invokes the external task again when polling on the old one fails' do
        action   = run_action plan
        action.world.silence_logger!
        action.external_service.will_fail
        action.output[:task][:progress].must_equal 0
        run_action action
        action.output[:task][:progress].must_equal 0
      end

      it 'tolerates some failure while polling' do
        action   = run_action plan
        action.external_service.will_fail
        action.world.silence_logger!

        TestPollingAction.config.poll_max_retries = 3
        (1..2).each do |attempt|
          progress_action_time action
          action.poll_attempts[:failed].must_equal attempt
          next_ping(action).wont_be_nil
          action.state.must_equal :suspended
        end

        progress_action_time action
        action.poll_attempts[:failed].must_equal 3
        next_ping(action).must_be_nil
        action.state.must_equal :error
      end

      it 'allows increasing poll interval in a time' do
        TestPollingAction.config.poll_intervals = [1, 2]
        TestPollingAction.config.attempts_before_next_interval = 1

        action   = run_action plan
        next_ping(action).when.must_equal 1
        progress_action_time action
        next_ping(action).when.must_equal 2
        progress_action_time action
        next_ping(action).when.must_equal 2
      end

    end
  end
end
