require_relative 'test_helper'

module Dynflow
  module MiddlewareTest

    describe 'Middleware' do
      let(:world) { WorldFactory.create_world }
      let(:log) { Support::MiddlewareExample::LogMiddleware.log }

      before do
        Support::MiddlewareExample::LogMiddleware.reset_log
      end

      it "wraps the action method calls" do
        delay = world.delay(Support::MiddlewareExample::LoggingAction, { :start_at => Time.now.utc - 60 }, {})
        plan = world.persistence.load_delayed_plan delay.execution_plan_id
        plan.plan
        plan.execute.future.wait
        log.must_equal %w[LogMiddleware::before_delay
                          delay
                          LogMiddleware::after_delay
                          LogMiddleware::before_plan_phase
                          LogMiddleware::before_plan
                          plan
                          LogMiddleware::after_plan
                          LogMiddleware::after_plan_phase
                          LogMiddleware::before_run
                          run
                          LogMiddleware::after_run
                          LogMiddleware::before_finalize_phase
                          LogMiddleware::before_finalize
                          finalize
                          LogMiddleware::after_finalize
                          LogMiddleware::after_finalize_phase]
      end

      it "inherits the middleware" do
        world.trigger(Support::MiddlewareExample::SubAction, {}).finished.wait
        log.must_equal %w[LogRunMiddleware::before_run
                          AnotherLogRunMiddleware::before_run
                          run
                          AnotherLogRunMiddleware::after_run
                          LogRunMiddleware::after_run]
      end

      describe "world.middleware" do
        let(:world_with_middleware) do
          WorldFactory.create_world.tap do |world|
            world.middleware.use(Support::MiddlewareExample::AnotherLogRunMiddleware)
          end
        end

        it "puts the middleware to the beginning of the stack" do
          world_with_middleware.trigger(Support::MiddlewareExample::Action, {}).finished.wait
          log.must_equal %w[AnotherLogRunMiddleware::before_run
                            LogRunMiddleware::before_run
                            run
                            LogRunMiddleware::after_run
                            AnotherLogRunMiddleware::after_run]
        end
      end

      describe "rules" do
        describe "before" do
          specify do
            world.trigger(Support::MiddlewareExample::SubActionBeforeRule, {}).finished.wait
            log.must_equal %w[AnotherLogRunMiddleware::before_run
                              LogRunMiddleware::before_run
                              run
                              LogRunMiddleware::after_run
                              AnotherLogRunMiddleware::after_run]
          end
        end

        describe "after" do
          let(:world_with_middleware) do
            WorldFactory.create_world.tap do |world|
              world.middleware.use(Support::MiddlewareExample::AnotherLogRunMiddleware,
                                   after: Support::MiddlewareExample::LogRunMiddleware)

            end
          end

          specify do
            world_with_middleware.trigger(Support::MiddlewareExample::Action, {}).finished.wait
            log.must_equal %w[LogRunMiddleware::before_run
                              AnotherLogRunMiddleware::before_run
                              run
                              AnotherLogRunMiddleware::after_run
                              LogRunMiddleware::after_run]
          end
        end

        describe "replace" do
          specify do
            world.trigger(Support::MiddlewareExample::SubActionReplaceRule, {}).finished.wait
            log.must_equal %w[AnotherLogRunMiddleware::before_run
                              run
                              AnotherLogRunMiddleware::after_run]
          end
        end

        describe "remove" do
          specify do
            world.trigger(Support::MiddlewareExample::SubActionDoNotUseRule, {}).finished.wait
            log.must_equal %w[run]
          end
        end
      end

      it "allows access the running action" do
        world = WorldFactory.create_world
        world.middleware.use(Support::MiddlewareExample::ObservingMiddleware,
                             replace: Support::MiddlewareExample::LogRunMiddleware)
        world.trigger(Support::MiddlewareExample::Action, message: 'hello').finished.wait
        log.must_equal %w[input#message:hello
                          run
                          output#message:finished]
      end

      it "allows modification of the running action when delaying execution" do
        world = WorldFactory.create_world
        world.middleware.use(Support::MiddlewareExample::AnotherObservingMiddleware,
                             replace: Support::MiddlewareExample::LogRunMiddleware)
        delay = world.delay(Support::MiddlewareExample::Action, { :start_at => Time.now - 60 })
        plan = world.persistence.load_delayed_plan delay.execution_plan_id
        plan.plan
        plan.execute.future.wait
        log.must_equal ["delay#set-input:#{world.id}",
                        "plan#input:#{world.id}",
                        "input#message:#{world.id}",
                        'run',
                        'output#message:finished']
      end

      describe 'Presnet middleware' do
        let(:world_with_middleware) do
          WorldFactory.create_world.tap do |world|
            world.middleware.use(Support::MiddlewareExample::FilterSensitiveData)
          end
        end

        let :execution_plan do
          result = world.trigger(Support::CodeWorkflowExample::IncomingIssue, issue_data)
          result.must_be :planned?
          result.finished.value
        end

        let :execution_plan_2 do
          result = world.trigger(Support::MiddlewareExample::SecretAction)
          result.must_be :planned?
          result.finished.value
        end

        let :filtered_execution_plan do
          world_with_middleware.persistence.load_execution_plan(execution_plan.id)
        end

        let :issue_data do
          { 'author' => 'Harry Potter', 'text' => 'Lord Voldemort is comming' }
        end

        let :presenter do
          filtered_execution_plan.root_plan_step.action filtered_execution_plan
        end

        let :presenter_2 do
          execution_plan_2.root_plan_step.action execution_plan_2
        end

        let :presenter_without_middleware do
          execution_plan.root_plan_step.action execution_plan
        end

        it 'filters the data ===' do
          presenter.input['text'].must_equal('You-Know-Who is comming')
          presenter_2.output['spell'].must_equal('***')
        end

        it "doesn't affect stored data" do
          presenter.input['text'].must_equal('You-Know-Who is comming')
          presenter_without_middleware.input['text'].must_equal('Lord Voldemort is comming')
        end
      end

    end
  end
end
