module Dynflow
  module Actors
    class ExecutionPlanCleaner
      attr_reader :core

      def initialize(world, options = {})
        @world = world
        @options = options
      end

      def core_class
        Core
      end

      def spawn
        Concurrent.future.tap do |initialized|
          @core = core_class.spawn(:name => 'execution-plan-cleaner',
                                   :args => [@world, @options],
                                   :initialized => initialized)
        end
      end

      def clean!
        core.tell([:clean!])
      end

      class Core < Actor
        def initialize(world, options = {})
          @world = world
          default_age = 60 * 60 * 24 # One day by default
          @poll_interval = options.fetch(:poll_interval, default_age)
          @max_age = options.fetch(:max_age, default_age)
          start
        end

        def start
          set_clock
          clean!
        end

        def clean!
          plans = @world.persistence.find_old_execution_plans(Time.now.utc - @max_age)
          report(plans)
          @world.persistence.delete_execution_plans(uuid: plans.map(&:id))
        end

        def report(plans)
          @world.logger.info("Execution plan cleaner removing #{plans.count} execution plans.")
        end

        def set_clock
          @world.clock.ping(self, @poll_interval, :start)
        end
      end
    end
  end
end
