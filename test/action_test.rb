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
        klass = Class.new(Dynflow::Action) do
          def run
            output.update key: Object.new
          end
        end
        action = create_and_plan_action klass, {}
        -> { run_action action }.must_raise NoMethodError
      end
    end

    describe '#humanized_state' do
      include Testing

      class ActionWithHumanizedState < Dynflow::Action
        def run(event = nil)
          suspend unless event
        end

        def humanized_state
          case state
          when :suspended
            "waiting"
          else
            super
          end
        end
      end

      it 'is customizable from an action' do
        plan   = create_and_plan_action ActionWithHumanizedState, {}
        action = run_action(plan)
        action.humanized_state.must_equal "waiting"
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

      class NonRunningExternalService < ExternalService
        def poll(id)
          return { message: 'nothing changed' }
        end
      end

      class TestTimeoutAction < TestPollingAction
        class Config < TestPollingAction::Config
          def initialize
            super
            @external_service = NonRunningExternalService.new
          end
        end

        def done?
          self.state == :error
        end

        def invoke_external_task
          schedule_timeout(5)
          super
        end
      end

      describe'without timeout' do
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
          action = run_action plan

          action.output[:task][:task_id].must_equal 123
        end

        it 'polls till the task is done' do
          action = run_action plan

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
          action = run_action plan
          action.output[:task][:progress].must_equal 0
          run_action action
          action.output[:task][:progress].must_equal 10
        end

        it 'invokes the external task again when polling on the old one fails' do
          action = run_action plan
          action.world.silence_logger!
          action.external_service.will_fail
          action.output[:task][:progress].must_equal 0
          run_action action
          action.output[:task][:progress].must_equal 0
        end

        it 'tolerates some failure while polling' do
          action = run_action plan
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
          TestPollingAction.config.attempts_before_next_interval = 2

          action = run_action plan
          pings = []
          pings << next_ping(action)
          progress_action_time action
          pings << next_ping(action)
          progress_action_time action
          pings << next_ping(action)
          progress_action_time action
          (pings[1].when - pings[0].when).must_be_close_to 1
          (pings[2].when - pings[1].when).must_be_close_to 2
        end
      end

      describe 'with timeout' do
        let(:plan) do
          create_and_plan_action TestTimeoutAction, { task_args: 'do something' }
        end

        before do
          TestTimeoutAction.config = TestTimeoutAction::Config.new
          TestTimeoutAction.config.poll_intervals = [2]
        end

        it 'timesout' do
          action = run_action plan
          iterations = 0
          while progress_action_time action
            # we count the number of iterations till the timeout occurs
            iterations += 1
          end
          action.state.must_equal :error
          # two polls in 2 seconds intervals untill the 5 seconds
          # timeout appears
          iterations.must_equal 3
        end
      end
    end

    describe Action::WithSubPlans do

      class FailureSimulator
        class << self
          attr_accessor :fail_in_child_plan, :fail_in_child_run

          def reset!
            self.fail_in_child_plan = self.fail_in_child_run = false
          end
        end
      end

      class ParentAction < Dynflow::Action

        include Dynflow::Action::WithSubPlans

        def create_sub_plans
          input[:count].times.map { trigger(ChildAction, suspend: input[:suspend]) }
        end

        def resume(*args)
          output[:custom_resume] = true
          super *args
        end
      end

      class ChildAction < Dynflow::Action
        include Dynflow::Action::Cancellable

        def plan(input)
          if FailureSimulator.fail_in_child_plan
            raise "Fail in child plan"
          end
          super
        end

        def run(event = nil)
          if FailureSimulator.fail_in_child_run
            raise "Fail in child run"
          end
          if event == Dynflow::Action::Cancellable::Abort
            output[:aborted] = true
          end
          if input[:suspend] && !cancel_event?(event)
            suspend
          end
        end

        def cancel_event?(event)
          event == Dynflow::Action::Cancellable::Cancel ||
            event == Dynflow::Action::Cancellable::Abort
        end
      end

      class PollingParentAction < ParentAction
        include ::Dynflow::Action::WithPollingSubPlans
      end

      class PollingBulkParentAction < ParentAction
        include ::Dynflow::Action::WithBulkSubPlans
        include ::Dynflow::Action::WithPollingSubPlans

        def poll
          output[:poll] += 1
          super
        end

        def on_planning_finished
          output[:poll] = 0
          output[:planning_finished] ||= 0
          output[:planning_finished] += 1
          super
        end

        def total_count
          input[:count]
        end

        def batch_size
          1
        end

        def create_sub_plans
          current_batch.map { trigger(ChildAction, suspend: input[:suspend]) }
        end

        def batch(from, size)
          total_count.times.drop(from).take(size)
        end

      end

      let(:execution_plan) { world.trigger(ParentAction, count: 2).finished.value }

      before do
        FailureSimulator.reset!
      end

      specify "the sub-plan stores the information about its parent" do
        sub_plans = execution_plan.sub_plans
        sub_plans.size.must_equal 2
        sub_plans.each { |sub_plan| sub_plan.caller_execution_plan_id.must_equal execution_plan.id }
      end

      specify "it saves the information about number for sub plans in the output" do
        execution_plan.entry_action.output.must_equal('total_count'   => 2,
                                                      'failed_count'  => 0,
                                                      'success_count' => 2,
                                                      'pending_count' => 0)
      end

      specify "when a sub plan fails, the caller action fails as well" do
        FailureSimulator.fail_in_child_run = true
        execution_plan.entry_action.output.must_equal('total_count'   => 2,
                                                      'failed_count'  => 2,
                                                      'success_count' => 0,
                                                      'pending_count' => 0)
        execution_plan.state.must_equal :paused
        execution_plan.result.must_equal :error
      end

      describe 'resuming' do
        specify "resuming the action depends on the resume method definition" do
          FailureSimulator.fail_in_child_plan = true
          execution_plan.state.must_equal :paused
          FailureSimulator.fail_in_child_plan = false
          resumed_plan = world.execute(execution_plan.id).value
          resumed_plan.entry_action.output[:custom_resume].must_equal true
        end

        specify "by default, when no sub plans were planned successfully, it call create_sub_plans again" do
          FailureSimulator.fail_in_child_plan = true
          execution_plan.state.must_equal :paused
          FailureSimulator.fail_in_child_plan = false
          resumed_plan = world.execute(execution_plan.id).value
          resumed_plan.state.must_equal :stopped
          resumed_plan.result.must_equal :success
        end

        specify "by default, when any sub-plan was planned, it succeeds only when the sub-plans were already finished" do
          FailureSimulator.fail_in_child_run = true
          execution_plan.state.must_equal :paused
          sub_plans = execution_plan.sub_plans

          FailureSimulator.fail_in_child_run = false
          resumed_plan = world.execute(execution_plan.id).value
          resumed_plan.state.must_equal :paused

          world.execute(sub_plans.first.id).wait
          resumed_plan = world.execute(execution_plan.id).value
          resumed_plan.state.must_equal :paused

          sub_plans.drop(1).each { |sub_plan| world.execute(sub_plan.id).wait }
          resumed_plan = world.execute(execution_plan.id).value
          resumed_plan.state.must_equal :stopped
          resumed_plan.result.must_equal :success
        end

        describe ::Dynflow::Action::WithPollingSubPlans do
          include TestHelpers

          let(:clock) { Dynflow::Testing::ManagedClock.new }
          let(:polling_plan) { world.trigger(PollingParentAction, count: 2).finished.value }

          specify "by default, when no sub plans were planned successfully, it calls create_sub_plans again" do
            world.stub(:clock, clock) do
              total = 2
              FailureSimulator.fail_in_child_plan = true
              triggered_plan = world.trigger(PollingParentAction, count: total)
              polling_plan = world.persistence.load_execution_plan(triggered_plan.id)

              wait_for do # Waiting for the sub plans to be spawned
                polling_plan = world.persistence.load_execution_plan(triggered_plan.id)
                polling_plan.sub_plans.count == total
              end

              # Moving the clock to make the parent check on sub plans
              clock.pending_pings.count.must_equal 1
              clock.progress

              wait_for do # Waiting for the parent to realise the sub plans failed
                polling_plan = world.persistence.load_execution_plan(triggered_plan.id)
                polling_plan.state == :paused
              end

              FailureSimulator.fail_in_child_plan = false

              world.execute(polling_plan.id) # The actual resume

              wait_for do # Waiting for new generation of sub plans to be spawned
                polling_plan.sub_plans.count == 2 * total
              end

              # Move the clock again
              clock.pending_pings.count.must_equal 1
              clock.progress

              wait_for do # Waiting for everything to finish successfully
                polling_plan = world.persistence.load_execution_plan(triggered_plan.id)
                polling_plan.state == :stopped && polling_plan.result == :success
              end
            end
          end

          specify "by default it starts polling again" do
            world.stub(:clock, clock) do
              total = 2
              FailureSimulator.fail_in_child_run = true
              triggered_plan = world.trigger(PollingParentAction, count: total)
              polling_plan = world.persistence.load_execution_plan(triggered_plan.id)

              wait_for do # Waiting for the sub plans to be spawned
                polling_plan = world.persistence.load_execution_plan(triggered_plan.id)
                polling_plan.sub_plans.count == total &&
                  polling_plan.sub_plans.all? { |sub| sub.state == :paused }
              end

              # Moving the clock to make the parent check on sub plans
              clock.pending_pings.count.must_equal 1
              clock.progress
              clock.pending_pings.count.must_equal 0

              wait_for do # Waiting for the parent to realise the sub plans failed
                polling_plan = world.persistence.load_execution_plan(triggered_plan.id)
                polling_plan.state == :paused
              end

              FailureSimulator.fail_in_child_run = false

              # Resume the sub plans
              polling_plan.sub_plans.each do |sub|
                world.execute(sub.id)
              end

              wait_for do # Waiting for the child tasks to finish
                polling_plan.sub_plans.all? { |sub| sub.state == :stopped }
              end

              world.execute(polling_plan.id) # The actual resume

              wait_for do # Waiting for everything to finish successfully
                polling_plan = world.persistence.load_execution_plan(triggered_plan.id)
                polling_plan.state == :stopped && polling_plan.result == :success
              end
            end
          end
        end
      end

      describe 'cancelling' do
        include TestHelpers

        it "sends the cancel event to all actions that are running and support cancelling" do
          triggered_plan = world.trigger(ParentAction, count: 2, suspend: true)
          plan = wait_for do
            plan = world.persistence.load_execution_plan(triggered_plan.id)
            if plan.cancellable?
              plan
            end
          end
          plan.cancel
          triggered_plan.finished.wait
          triggered_plan.finished.value.state.must_equal :stopped
          triggered_plan.finished.value.result.must_equal :success
        end

        it "sends the abort event to all actions that are running and support cancelling" do
          triggered_plan = world.trigger(ParentAction, count: 2, suspend: true)
          plan = wait_for do
            plan = world.persistence.load_execution_plan(triggered_plan.id)
            if plan.cancellable?
              plan
            end
          end
          plan.cancel true
          triggered_plan.finished.wait
          triggered_plan.finished.value.state.must_equal :stopped
          triggered_plan.finished.value.result.must_equal :success
          plan.sub_plans.each do |sub_plan|
            sub_plan.entry_action.output[:aborted].must_equal true
          end
        end
      end

      describe ::Dynflow::Action::WithPollingSubPlans do
        include TestHelpers

        let(:clock) { Dynflow::Testing::ManagedClock.new }

        specify 'polls for sub plans state' do
          world.stub :clock, clock do
            total = 2
            plan = world.plan(PollingParentAction, count: total)
            plan.state.must_equal :planned
            world.execute(plan.id)
            clock.pending_pings.count.must_equal 0
            wait_for do
              plan.sub_plans.count == total &&
                plan.sub_plans.all? { |sub| sub.result == :success }
            end
            clock.pending_pings.count.must_equal 1
            clock.progress
            wait_for do
              plan = world.persistence.load_execution_plan(plan.id)
              plan.state == :stopped
            end
            clock.pending_pings.count.must_equal 0
          end
        end

        specify 'starts polling for sub plans at the beginning' do
          world.stub :clock, clock do
            total = 2
            plan = world.plan(PollingBulkParentAction, count: total)
            assert_nil plan.entry_action.output[:planning_finished]
            clock.pending_pings.count.must_equal 0
            world.execute(plan.id)
            wait_for do
              plan = world.persistence.load_execution_plan(plan.id)
              plan.entry_action.output[:planning_finished] == 1
            end
            # Poll was set during #initiate
            clock.pending_pings.count.must_equal 1

            # Wait for the sub plans to finish
            wait_for do
              plan.sub_plans.count == total &&
                plan.sub_plans.all? { |sub| sub.result == :success }
            end

            # Poll again
            clock.progress
            wait_for do
              plan = world.persistence.load_execution_plan(plan.id)
              plan.state == :stopped
            end
            plan.entry_action.output[:poll].must_equal 1
            clock.pending_pings.count.must_equal 0
          end
        end

        describe ::Dynflow::Action::Singleton do
          include TestHelpers

          let(:clock) { Dynflow::Testing::ManagedClock.new }

          class SingletonAction < ::Dynflow::Action
            include ::Dynflow::Action::Singleton
            middleware.use ::Dynflow::Middleware::Common::Singleton
          end

          class SingletonActionWithRun < SingletonAction
            def run; end
          end

          class SingletonActionWithFinalize < SingletonAction
            def finalize; end
          end

          class SuspendedSingletonAction < SingletonAction
            def run(event = nil)
              unless output[:suspended]
                output[:suspended] = true
                suspend
              end
            end
          end

          class BadAction < SingletonAction
            def plan(break_locks = false)
              plan_self :break_locks => break_locks
              singleton_unlock! if break_locks
            end

            def run
              singleton_unlock! if input[:break_locks]
            end
          end

          it 'unlocks the locks after #plan if no #run or #finalize' do
            plan = world.plan(SingletonAction)
            plan.state.must_equal :planned
            lock_filter = ::Dynflow::Coordinator::SingletonActionLock
                              .unique_filter plan.entry_action.class.name
            world.coordinator.find_locks(lock_filter).must_be :empty?
            plan = world.execute(plan.id).wait!.value
            plan.state.must_equal :stopped
            plan.result.must_equal :success
            world.coordinator.find_locks(lock_filter).must_be :empty?
          end

          it 'unlocks the locks after #finalize' do
            plan = world.plan(SingletonActionWithFinalize)
            plan.state.must_equal :planned
            lock_filter = ::Dynflow::Coordinator::SingletonActionLock
                              .unique_filter plan.entry_action.class.name
            world.coordinator.find_locks(lock_filter).count.must_equal 1
            plan = world.execute(plan.id).wait!.value
            plan.state.must_equal :stopped
            plan.result.must_equal :success
            world.coordinator.find_locks(lock_filter).count.must_equal 0
          end

          it 'does not unlock when getting suspended' do
            plan = world.plan(SuspendedSingletonAction)
            plan.state.must_equal :planned
            lock_filter = ::Dynflow::Coordinator::SingletonActionLock
                              .unique_filter plan.entry_action.class.name
            world.coordinator.find_locks(lock_filter).count.must_equal 1
            future = world.execute(plan.id)
            wait_for do
              plan = world.persistence.load_execution_plan(plan.id)
              plan.state == :running && plan.result == :pending
            end
            world.coordinator.find_locks(lock_filter).count.must_equal 1
            world.event(plan.id, 2, nil)
            plan = future.wait!.value
            plan.state.must_equal :stopped
            plan.result.must_equal :success
            world.coordinator.find_locks(lock_filter).count.must_equal 0
          end

          it 'can be triggered only once' do
            # plan1 acquires the lock in plan phase
            plan1 = world.plan(SingletonActionWithRun)
            plan1.state.must_equal :planned
            plan1.result.must_equal :pending

            # plan2 tries to acquire the lock in plan phase and fails
            plan2 = world.plan(SingletonActionWithRun)
            plan2.state.must_equal :stopped
            plan2.result.must_equal :error
            plan2.errors.first.message.must_equal 'Action Dynflow::SingletonActionWithRun is already active'

            # Simulate some bad things happening
            plan1.entry_action.send(:singleton_unlock!)

            # plan3 acquires the lock in plan phase
            plan3 = world.plan(SingletonActionWithRun)

            # plan1 tries to relock on run
            # This should fail because the lock was taken by plan3
            plan1 = world.execute(plan1.id).wait!.value
            plan1.state.must_equal :paused
            plan1.result.must_equal :error

            # plan3 can finish successfully because it holds the lock
            plan3 = world.execute(plan3.id).wait!.value
            plan3.state.must_equal :stopped
            plan3.result.must_equal :success

            # The lock was released when plan3 stopped
            lock_filter = ::Dynflow::Coordinator::SingletonActionLock
                              .unique_filter plan3.entry_action.class.name
            world.coordinator.find_locks(lock_filter).must_be :empty?
          end

          it 'cannot be unlocked by another action' do
            # plan1 doesn't keep its locks
            plan1 = world.plan(BadAction, true)
            plan1.state.must_equal :planned
            lock_filter = ::Dynflow::Coordinator::SingletonActionLock
                              .unique_filter plan1.entry_action.class.name
            world.coordinator.find_locks(lock_filter).count.must_equal 0
            plan2 = world.plan(BadAction, false)
            plan2.state.must_equal :planned
            world.coordinator.find_locks(lock_filter).count.must_equal 1

            # The locks held by plan2 can't be unlocked by plan1
            plan1.entry_action.singleton_unlock!
            world.coordinator.find_locks(lock_filter).count.must_equal 1

            plan1 = world.execute(plan1.id).wait!.value
            plan1.state.must_equal :paused
            plan1.result.must_equal :error

            plan2 = world.execute(plan2.id).wait!.value
            plan2.state.must_equal :stopped
            plan2.result.must_equal :success
          end
        end
      end
    end
  end
end
