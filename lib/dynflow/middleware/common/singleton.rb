# frozen_string_literal: true

module Dynflow
  module Middleware::Common
    class Singleton < Middleware
      # Each action tries to acquire its own lock before the action's #plan starts
      def plan(*args, **kwargs)
        action.singleton_lock!
        pass(*args, **kwargs)
      end

      # At the start of #run we try to acquire action's lock unless it already holds it
      # At the end the action tries to unlock its own lock if the execution plan has no
      #   finalize phase
      def run(*args)
        action.singleton_lock! unless action.holds_singleton_lock?
        pass(*args)
      end
    end
  end
end
