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
            middleware.pass
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

    describe 'Middleware' do
      let(:world) { WorldInstance.world }

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
          attr_reader :input, :output, :stack

          def initialize
            classes = [Test1Middleware, Test2Middleware, Test3Middleware]
            @stack = Middleware::Stack.new(classes)
          end

          def plan(arg)
            @input = arg
            @output = []
          end
        end

        class AlmostActionNestedCall < AlmostAction

          def plan(arg)
            stack.evaluate(:plan_self, self, arg)
            @output = []
          end

          def plan_self(arg)
            @input = arg
          end
        end

        class TestMiddleware < Dynflow::Middleware
          def plan(arg)
            stack.pass(arg << "IN: #{self.class.name}").tap do |ret|
              action.output << "OUT: #{self.class.name}"
            end
          end
        end

        class Test1Middleware < TestMiddleware
        end

        class Test2Middleware < TestMiddleware
        end

        class Test3Middleware < Dynflow::Middleware
          def plan_self(arg)
            stack.pass(arg).tap do
              action.input.map!(&:upcase)
            end
          end
        end

        it 'calls the method recursively through the stack, skipping the middlewares without the method defined ' do
          action = AlmostAction.new
          action.stack.evaluate(:plan, action, [])
          action.input.must_equal ["IN: Dynflow::MiddlewareTest::Test1Middleware", "IN: Dynflow::MiddlewareTest::Test2Middleware"]
          action.output.must_equal ["OUT: Dynflow::MiddlewareTest::Test2Middleware", "OUT: Dynflow::MiddlewareTest::Test1Middleware"]
        end

        it 'allows nested calls on the same stack' do
          action = AlmostActionNestedCall.new
          action.stack.evaluate(:plan, action, [])
          action.input.must_equal ["IN: DYNFLOW::MIDDLEWARETEST::TEST1MIDDLEWARE", "IN: DYNFLOW::MIDDLEWARETEST::TEST2MIDDLEWARE"]
          action.output.must_equal ["OUT: Dynflow::MiddlewareTest::Test2Middleware", "OUT: Dynflow::MiddlewareTest::Test1Middleware"]
        end

      end
    end
  end
end
