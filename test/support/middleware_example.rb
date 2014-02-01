module Support
  module MiddlewareExample
    class LogMiddleware < Dynflow::Middleware

      def self.log
        @log
      end

      def self.reset_log
        @log = []
      end

      def log(message)
        LogMiddleware.log << "#{self.class.name[/\w+$/]}::#{message}"
      end

      def plan(args)
        log 'before_plan'
        pass(args)
        log 'after_plan'
      end

      def run
        log 'before_run'
        pass
        log 'after_run'
      end

      def finalize
        log 'before_finalize'
        pass
        log 'after_finalize'
      end

      def plan_phase
        log 'before_plan_phase'
        pass
        log 'after_plan_phase'
      end

      def finalize_phase
        log 'before_finalize_phase'
        pass
        log 'after_finalize_phase'
      end

    end

    class LogRunMiddleware < Dynflow::Middleware

      def log(message)
        LogMiddleware.log << "#{self.class.name[/\w+$/]}::#{message}"
      end

      def run
        log 'before_run'
        pass
        log 'after_run'
      end
    end

    class AnotherLogRunMiddleware < LogRunMiddleware
    end

    class LoggingAction < Dynflow::Action

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

    class ObservingMiddleware < Dynflow::Middleware

      def log(message)
        LogMiddleware.log << message
      end

      def run(*args)
        log("input#message:#{action.input[:message]}")
        pass(*args)
      ensure
        log("output#message:#{action.output[:message]}")
      end
    end

    class Action < Dynflow::Action
      middleware.use LogRunMiddleware

      def log(message)
        LogMiddleware.log << message
      end

      def run
        log("run")
        output[:message] = "finished"
      end
    end

    class SubAction < Action
      middleware.use AnotherLogRunMiddleware
    end

    class SubActionBeforeRule < Action
      middleware.use AnotherLogRunMiddleware, before: LogRunMiddleware
    end

    class SubActionReplaceRule < Action
      middleware.use AnotherLogRunMiddleware, replace: LogRunMiddleware
    end

    class SubActionAfterRule < Action
      middleware.use AnotherLogRunMiddleware, after: LogRunMiddleware
    end
  end
end
