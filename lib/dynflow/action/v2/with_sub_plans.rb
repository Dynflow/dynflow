# frozen_string_literal: true

module Dynflow::Action::V2
  module WithSubPlans
    include Dynflow::Action::Cancellable

    DEFAULT_BATCH_SIZE = 100
    DEFAULT_POLLING_INTERVAL = 15
    Ping = Algebrick.atom

    class SubtaskFailedException < RuntimeError
      def backtrace
        []
      end
    end

    # Methods to be overridden
    def create_sub_plans
      raise NotImplementedError
    end

    # Should return the expected total count of tasks
    def total_count
      raise NotImplementedError
    end

    def batch_size
      DEFAULT_BATCH_SIZE
    end

    # Should return a slice of size items starting from item with index from
    def batch(from, size)
      raise NotImplementedError
    end

    # Polling
    def polling_interval
      DEFAULT_POLLING_INTERVAL
    end

    # Callbacks
    def on_finish
    end

    def on_planning_finished
    end

    def run(event = nil)
      case event
      when nil
        if output[:total_count]
          resume
        else
          initiate
        end
      when Ping
        tick
      when ::Dynflow::Action::Cancellable::Cancel
        cancel!
      when ::Dynflow::Action::Cancellable::Abort
        abort!
      end
      try_to_finish || suspend_and_ping
    end

    def initiate
      output[:planned_count] = 0
      output[:cancelled_count] = 0
      output[:total_count] = total_count
      spawn_plans
    end

    def resume
      if sub_plans.all? { |sub_plan| sub_plan.error_in_plan? }
        output[:resumed_count] ||= 0
        output[:resumed_count] += output[:failed_count]
        # We're starting over and need to reset the counts
        %w(total failed pending success).each { |key| output.delete("#{key}_count".to_sym) }
        initiate
      else
        tick
      end
    end

    def tick
      recalculate_counts
      spawn_plans if can_spawn_next_batch?
    end

    def suspend_and_ping
      delay = (concurrency_limit.nil? || concurrency_limit_capacity > 0) && can_spawn_next_batch? ? nil : polling_interval
      plan_event(Ping, delay)
      suspend
    end

    def spawn_plans
      sub_plans = create_sub_plans
      sub_plans = Array[sub_plans] unless sub_plans.is_a? Array
      increase_counts(sub_plans.count, 0)
      on_planning_finished unless can_spawn_next_batch?
    end

    def increase_counts(planned, failed)
      output[:planned_count] += planned + failed
      output[:failed_count]  = output.fetch(:failed_count, 0) + failed
      output[:pending_count] = output.fetch(:pending_count, 0) + planned
      output[:success_count] ||= 0
    end

    def try_to_finish
      return false unless done?

      check_for_errors!
      on_finish
      true
    end

    def done?
      return false if can_spawn_next_batch? || !counts_set?

      total_count - output[:success_count] - output[:failed_count] - output[:cancelled_count] <= 0
    end

    def run_progress
      return 0.1 unless counts_set? && total_count > 0

      sum = output.values_at(:success_count, :cancelled_count, :failed_count).reduce(:+)
      sum.to_f / total_count
    end

    def recalculate_counts
      total   = total_count
      failed  = sub_plans_count('state' => %w(paused stopped), 'result' => %w(error warning))
      success = sub_plans_count('state' => 'stopped', 'result' => 'success')
      output.update(:pending_count => total - failed - success,
                    :failed_count  => failed - output.fetch(:resumed_count, 0),
                    :success_count => success)
    end

    def counts_set?
      output[:total_count] && output[:success_count] && output[:failed_count] && output[:pending_count]
    end

    def check_for_errors!
      raise SubtaskFailedException.new("A sub task failed") if output[:failed_count] > 0
    end

    # Helper for creating sub plans
    def trigger(action_class, *args, **kwargs)
      world.trigger { world.plan_with_options(action_class: action_class, args: args, kwargs: kwargs, caller_action: self) }
    end

    # Concurrency limitting
    def limit_concurrency_level!(level)
      input[:dynflow] ||= {}
      input[:dynflow][:concurrency_limit] = level
    end

    def concurrency_limit
      input[:dynflow] ||= {}
      input[:dynflow][:concurrency_limit]
    end

    def concurrency_limit_capacity
      if limit = concurrency_limit
        return limit unless counts_set?
        capacity = limit - (output[:planned_count] - (output[:success_count] + output[:failed_count]))
        [0, capacity].max
      end
    end

    # Cancellation handling
    def cancel!(force = false)
      # Count the not-yet-planned tasks as cancelled
      output[:cancelled_count] = total_count - output[:planned_count]
      on_planning_finished if output[:cancelled_count].positive?
      # Pass the cancel event to running sub plans if they can be cancelled
      sub_plans(:state => 'running').each { |sub_plan| sub_plan.cancel(force) if sub_plan.cancellable? }
      suspend
    end

    def abort!
      cancel! true
    end

    # Batching
    # Returns the items in the current batch
    def current_batch
      start_position = output[:planned_count]
      size = batch_size
      size = concurrency_limit_capacity if concurrency_limit
      size = start_position + size > total_count ? total_count - start_position : size
      batch(start_position, size)
    end

    def can_spawn_next_batch?
      remaining_count > 0
    end

    def remaining_count
      total_count - output[:cancelled_count] - output[:planned_count]
    end

    private

    # Sub-plan lookup
    def sub_plan_filter
      { 'caller_execution_plan_id' => execution_plan_id,
        'caller_action_id' => self.id }
    end

    def sub_plans(filter = {})
      world.persistence.find_execution_plans(filters: sub_plan_filter.merge(filter))
    end

    def sub_plans_count(filter = {})
      world.persistence.find_execution_plan_counts(filters: sub_plan_filter.merge(filter))
    end
  end
end
