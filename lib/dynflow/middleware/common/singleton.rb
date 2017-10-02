module Dynflow
  module Middleware::Common
    class Singleton < Middleware
      def plan(*args)
        action.singleton_lock!
        pass(*args)
        unless action.respond_to?(:run) || action.respond_to?(:finalize)  
          action.singleton_unlock!
        end
      end

      def run(*args)
        action.singleton_lock! unless action.holds_singleton_lock?
        pass(*args)
        action.singleton_unlock! unless action.respond_to?(:finalize)
      end

      def finalize(*args)
        pass(*args)
        action.singleton_unlock!
      end
    end
  end
end
