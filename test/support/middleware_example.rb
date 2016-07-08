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

      def delay(*args)
        log 'before_delay'
        pass *args
        log 'after_delay'
      end

      def plan(args)
        log 'before_plan'
        pass(args)
        log 'after_plan'
      end

      def run(*args)
        log 'before_run'
        pass(*args)
      ensure
        log 'after_run'
      end

      def finalize
        log 'before_finalize'
        pass
        log 'after_finalize'
      end

      def plan_phase(*_)
        log 'before_plan_phase'
        pass
        log 'after_plan_phase'
      end

      def finalize_phase(*_)
        log 'before_finalize_phase'
        pass
        log 'after_finalize_phase'
      end

    end

    class LogRunMiddleware < Dynflow::Middleware

      def log(message)
        LogMiddleware.log << "#{self.class.name[/\w+$/]}::#{message}"
      end

      def run(*args)
        log 'before_run'
        pass(*args)
      ensure
        log 'after_run'
      end
    end

    class AnotherLogRunMiddleware < LogRunMiddleware
    end

    class FilterSensitiveData < Dynflow::Middleware
      def present
        if action.respond_to?(:filter_sensitive_data)
          action.filter_sensitive_data
        end
        filter_sensitive_data(action.input)
        filter_sensitive_data(action.output)
      end

      def filter_sensitive_data(data)
        case data
        when Hash
          data.values.each { |value| filter_sensitive_data(value) }
        when Array
          data.each { |value| filter_sensitive_data(value) }
        when String
          data.gsub!('Lord Voldemort', 'You-Know-Who')
        end
      end
    end

    class SecretAction < Dynflow::Action
      middleware.use(FilterSensitiveData)

      def run
        output[:spell] = 'Wingardium Leviosa'
      end

      def filter_sensitive_data
        output[:spell] = '***'
      end
    end

    class LoggingAction < Dynflow::Action

      middleware.use LogMiddleware

      def log(message)
        LogMiddleware.log << message
      end

      def delay(delay_options, *args)
        log 'delay'
        Dynflow::Serializers::Noop.new(args)
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

    class AnotherObservingMiddleware < ObservingMiddleware

      def delay(*args)
        pass(*args).tap do
          log("delay#set-input:#{action.world.id}")
          action.input[:message] = action.world.id
        end
      end

      def plan(*args)
        log("plan#input:#{action.input[:message]}")
        pass(*args)
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

    class SubActionDoNotUseRule < Action
      middleware.use AnotherLogRunMiddleware
      middleware.do_not_use AnotherLogRunMiddleware
      middleware.do_not_use LogRunMiddleware
    end

    class SubActionAfterRule < Action
      middleware.use AnotherLogRunMiddleware, after: LogRunMiddleware
    end
  end
end
