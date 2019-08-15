# frozen_string_literal: true
module Dynflow
  module DelayedExecutors
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

      def check_delayed_plans
        raise NotImplementedError
      end

      private

      def time
        @time_source.call()
      end

      def delayed_execution_plans(time)
        with_error_handling([]) do
          world.persistence.find_past_delayed_plans(time)
        end
      end

      def with_error_handling(error_retval = nil, &block)
        block.call
      rescue Exception => e
        @logger.warn e.message
        @logger.debug e.backtrace.join("\n")
        error_retval
      end

      def process(delayed_plans, check_time)
        processed_plan_uuids = []
        delayed_plans.each do |plan|
          next if plan.frozen
          fix_plan_state(plan)
          with_error_handling do
            if plan.execution_plan.state != :scheduled
              # in case the previous process was terminated after running the plan, but before deleting the delayed plan record.
              @logger.info("Execution plan #{plan.execution_plan_uuid} is expected to be in 'scheduled' state, was '#{plan.execution_plan.state}', skipping")
            elsif !plan.start_before.nil? && plan.start_before < check_time
              @logger.debug "Failing plan #{plan.execution_plan_uuid}"
              plan.timeout
            else
              @logger.debug "Executing plan #{plan.execution_plan_uuid}"
              Executors.run_user_code do
                plan.plan
                plan.execute
              end
            end
            processed_plan_uuids << plan.execution_plan_uuid
          end
        end
        world.persistence.delete_delayed_plans(:execution_plan_uuid => processed_plan_uuids) unless processed_plan_uuids.empty?
      end

      private

      # handle the case, where the process was termintated while planning was in progress before
      def fix_plan_state(plan)
        if plan.execution_plan.state == :planning
          @logger.info("Execution plan #{plan.execution_plan_uuid} is expected to be in 'scheduled' state, was '#{plan.execution_plan.state}', auto-fixing")
          plan.execution_plan.set_state(:scheduled, true)
          plan.execution_plan.save
        end
      end
    end
  end
end
