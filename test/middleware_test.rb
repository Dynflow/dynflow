require_relative 'test_helper'
require 'forwardable'

module Dynflow
  module MiddlewareTest

    class ActionException < StandardError
    end

    class AsUserMiddleware < Dynflow::Middleware
    end

    class NoopMiddleware < Dynflow::Middleware
    end

    class NotUsedMiddleware < Dynflow::Middleware
    end

    class CloseConnectionsMiddleware < Dynflow::Middleware
    end

    class RetryMiddleware < Dynflow::Middleware

      def run
        3.times do |attempt|
          begin
            pass
            break
          rescue ActionException => e
            raise e if attempt == 2
          end
        end
      end

    end

    # simulate a hierarchy of dynflow actions
    class DevopsAction < Dynflow::Action

      middleware.use NoopMiddleware
      middleware.use RetryMiddleware

    end

    class BuildImage < DevopsAction

      middleware.use AsUserMiddleware, before: RetryMiddleware

      def run
      end

      def finalize
      end

    end

    class ProvisionHost < DevopsAction
      middleware.use NoopMiddleware, replace: RetryMiddleware
    end

    class ConfigureHost < DevopsAction
      middleware.use AsUserMiddleware, after: NotUsedMiddleware
    end

    DevopsAction.middleware.use CloseConnectionsMiddleware

    class LogMiddleware < Dynflow::Middleware

      def self.log
        @log
      end

      def self.reset_log
        @log = []
      end

      def log(message)
        self.class.log << message
      end

      def plan(args)
        log 'before plan'
        pass(args)
        log 'after plan'
      end

      def run
        log 'before run'
        pass
        log 'after run'
      end

      def finalize
        log 'before finalize'
        pass
        log 'after finalize'
      end

      def plan_phase
        log 'before plan_phase'
        pass
        log 'after plan_phase'
      end

      def finalize_phase
        log 'before finalize_phase'
        pass
        log 'after finalize_phase'
      end

    end

    class TestingAction < Dynflow::Action

      middleware.use LogMiddleware

      def log(message)
        LogMiddleware.log << message
      end

      def plan(input)
        log 'plan'
        plan_self(input)
      end

      def run
        log 'run'
      end

      def finalize
        log 'finalize'
      end
    end

    describe 'Middleware' do
      let(:world) { WorldInstance.world }

      describe 'invocation' do

        before do
          LogMiddleware.reset_log
        end

        it 'calls the middleware methods when executing the plan' do
          run = world.trigger(TestingAction, {})
          run.finished.wait
          LogMiddleware.log.must_equal []
        end

      end

      describe 'rules resolution' do
        it 'sorts the middleware based on the specified rules' do
          rules = DevopsAction.middleware.rules.merge(BuildImage.middleware.rules)
          resolver = Dynflow::Middleware::Resolver.new(rules)
          resolver.result.must_equal [NoopMiddleware,
                                      AsUserMiddleware,
                                      RetryMiddleware,
                                      CloseConnectionsMiddleware]
        end

        it 'replaces the middleware based on the specified rules' do
          rules = DevopsAction.middleware.rules.merge(ProvisionHost.middleware.rules)
          resolver = Dynflow::Middleware::Resolver.new(rules)
          resolver.result.must_equal [NoopMiddleware,
                                      CloseConnectionsMiddleware]
        end

        it "ignores the rules related to classes not presented in the action's stack" do
          rules = DevopsAction.middleware.rules.merge(ConfigureHost.middleware.rules)
          resolver = Dynflow::Middleware::Resolver.new(rules)
          resolver.result.must_equal [NoopMiddleware,
                                      RetryMiddleware,
                                      CloseConnectionsMiddleware,
                                      AsUserMiddleware]
        end

      end

      describe 'stack' do

        class AlmostAction
          attr_reader :input, :output

          def self.create_stack(method, action = nil, &block)
            classes = [Test1Middleware, Test2Middleware, Test3Middleware]
            block ||= ->(*args) do
              action.send(method, *args)
            end
            Middleware::Stack.new(classes, method, action, &block)
          end

          def plan_with_middleware(*args)
            self.class.create_stack(:plan, self).pass(*args)
          end

          def plan_self_with_middleware(input)
            self.class.create_stack(:plan_self, self).pass(input)
          end

          def initialize
          end

          def plan(arg)
            @input = arg
            @output = []
          end
        end

        class AlmostActionNestedCall < AlmostAction

          def plan(arg)
            plan_self_with_middleware(arg)
            @output = []
          end

          def plan_self(arg)
            @input = arg
          end
        end

        class TestMiddleware < Dynflow::Middleware
          def plan(arg)
            pass(arg << "IN: #{self.class.name}").tap do |ret|
              action.output << "OUT: #{self.class.name}"
            end
          end
        end

        class Test1Middleware < TestMiddleware
        end

        class Test2Middleware < TestMiddleware
          def plan_phase
            pass.upcase
          end
        end

        class Test3Middleware < Dynflow::Middleware
          def plan_self(arg)
            pass(arg).tap do
              action.input.map!(&:upcase)
            end
          end
        end

        it 'calls the method recursively through the stack, skipping the middlewares without the method defined ' do
          action = AlmostAction.new
          action.plan_with_middleware([])
          action.input.must_equal ["IN: Dynflow::MiddlewareTest::Test1Middleware", "IN: Dynflow::MiddlewareTest::Test2Middleware"]
          action.output.must_equal ["OUT: Dynflow::MiddlewareTest::Test2Middleware", "OUT: Dynflow::MiddlewareTest::Test1Middleware"]
        end

        it 'allows nested calls on the same stack' do
          action = AlmostActionNestedCall.new
          action.plan_with_middleware([])
          action.input.must_equal ["IN: DYNFLOW::MIDDLEWARETEST::TEST1MIDDLEWARE", "IN: DYNFLOW::MIDDLEWARETEST::TEST2MIDDLEWARE"]
          action.output.must_equal ["OUT: Dynflow::MiddlewareTest::Test2Middleware", "OUT: Dynflow::MiddlewareTest::Test1Middleware"]
        end

        it 'allows calling the middleware with passing a block instead of action' do
          stack = AlmostAction.create_stack(:plan_phase) do
            "hello world"
          end
          output = stack.pass
          output.must_equal "HELLO WORLD"
        end

      end
    end
  end
end
