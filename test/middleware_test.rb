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
    end
  end
end
