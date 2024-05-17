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
          world.persistence.find_ready_delayed_plans(time)
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
        dispatched_plan_uuids = []
        planning_locks = world.coordinator.find_records(class: Coordinator::PlanningLock.name)
        delayed_plans.each do |plan|
          next if plan.frozen || locked_for_planning?(planning_locks, plan)
          fix_plan_state(plan)
          with_error_handling do
            if plan.execution_plan.state != :scheduled
              # in case the previous process was terminated after running the plan, but before deleting the delayed plan record.
              @logger.info("Execution plan #{plan.execution_plan_uuid} is expected to be in 'scheduled' state, was '#{plan.execution_plan.state}', skipping")
              processed_plan_uuids << plan.execution_plan_uuid
            else
              @logger.debug "Executing plan #{plan.execution_plan_uuid}"
              world.plan_request(plan.execution_plan_uuid)
              dispatched_plan_uuids << plan.execution_plan_uuid
            end
          end
        end
        world.persistence.delete_delayed_plans(:execution_plan_uuid => processed_plan_uuids) unless processed_plan_uuids.empty?
      end

      private

      # handle the case, where the process was termintated while planning was in progress before
      # TODO: Doing execution plan updates in orchestrator is bad
      def fix_plan_state(plan)
        if plan.execution_plan.state == :planning
          @logger.info("Execution plan #{plan.execution_plan_uuid} is expected to be in 'scheduled' state, was '#{plan.execution_plan.state}', auto-fixing")
          plan.execution_plan.set_state(:scheduled, true)
          plan.execution_plan.save
        end
      end

      def locked_for_planning?(planning_locks, plan)
        planning_locks.any? { |lock| lock.execution_plan_id == plan.execution_plan_uuid }
      end
    end
  end
end
