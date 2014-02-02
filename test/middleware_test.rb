require_relative 'test_helper'

module Dynflow
  module MiddlewareTest

    describe 'Middleware' do
      let(:world) { WorldInstance.world }
      let(:log) { Support::MiddlewareExample::LogMiddleware.log }

      before do
        Support::MiddlewareExample::LogMiddleware.reset_log
      end

      it "wraps the action method calls" do
        world.trigger(Support::MiddlewareExample::LoggingAction, {}).finished.wait
        log.must_equal %w[LogMiddleware::before_plan_phase
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
          WorldInstance.create_world.tap do |world|
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
            WorldInstance.create_world.tap do |world|
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
      end

      it "allows access the running action" do
        world = WorldInstance.create_world
        world.middleware.use(Support::MiddlewareExample::ObservingMiddleware,
                             replace: Support::MiddlewareExample::LogRunMiddleware)
        world.trigger(Support::MiddlewareExample::Action, message: 'hello').finished.wait
        log.must_equal %w[input#message:hello
                          run
                          output#message:finished]
      end
    end
  end
end
