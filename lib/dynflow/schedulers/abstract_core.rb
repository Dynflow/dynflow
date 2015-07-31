module Dynflow
  module Schedulers
    class AbstractCore < Actor

      include Algebrick::TypeCheck
      attr_reader :world, :logger

      def initialize(world, options = {})
        @world = Type! world, World
        @logger = world.logger
        configure(options)
      end

      def start
        raise NotImplementedError
      end

      def configure(options)
        @time_source = options.fetch(:time_source, -> { Time.now.utc })
      end

      def check_schedule
        raise NotImplementedError
      end

      private

      def time
        @time_source.call()
      end

      def scheduled_execution_plans(time)
        with_error_handling([]) do
          world.persistence.find_past_scheduled_plans(time)
        end
      end

      def with_error_handling(error_retval = nil, &block)
        block.call
      rescue Exception => e
        @logger.fatal e.backtrace.join("\n")
        error_retval
      end

      def process(scheduled_plans, check_time)
        processed_plan_uuids = []
        scheduled_plans.each do |plan|
          with_error_handling do
            if !plan.start_before.nil? && plan.start_before < check_time
              @logger.debug "Failing plan #{plan.execution_plan_uuid}"
              plan.timeout
            else
              @logger.debug "Executing plan #{plan.execution_plan_uuid}"
              plan.plan
              plan.execute
            end
            processed_plan_uuids << plan.execution_plan_uuid
          end
        end
        world.persistence.delete_scheduled_plans(:execution_plan_uuid => processed_plan_uuids) unless processed_plan_uuids.empty?
      end

    end
  end
end
