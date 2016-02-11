module Dynflow
  module Action::WithSubPlans
    include Dynflow::Action::Cancellable

    SubPlanFinished = Algebrick.type do
      fields! :execution_plan_id => String,
              :success           => type { variants TrueClass, FalseClass }
    end

    def run(event = nil)
      match event,
            (on nil do
               if output[:total_count]
                 resume
               else
                 initiate
               end
             end),
            (on SubPlanFinished do
               mark_as_done(event.execution_plan_id, event.success)
               try_to_finish or suspend
             end),
            (on Action::Cancellable::Cancel do
               cancel!
             end)
    end

    def initiate
      sub_plans = create_sub_plans
      sub_plans = Array[sub_plans] unless sub_plans.is_a? Array
      if uses_concurrency_control
        planned, failed = sub_plans.partition { |plan| plan.state == :planned }
        calculate_time_distribution sub_plans.count
        sub_plans = world.throttle_limiter.handle_plans!(execution_plan_id,
                                                         planned.map(&:id),
                                                         failed.map(&:id),
                                                         input[:concurrency_control])
      end
      wait_for_sub_plans sub_plans
    end

    # @abstract when the logic for the initiation of the subtasks
    #      is different from the default one.
    # @returns a triggered task or array of triggered tasks
    # @example
    #
    #        def create_sub_plans
    #          trigger(MyAction, "Hello")
    #        end
    #
    # @example
    #
    #        def create_sub_plans
    #          [trigger(MyAction, "Hello 1"), trigger(MyAction, "Hello 2")]
    #        end
    #
    def create_sub_plans
      raise NotImplementedError
    end

    # @api method to be called after all the sub tasks finished
    def on_finish
    end

    def cancel!
      @world.throttle_limiter.cancel!(execution_plan_id)
      sub_plans('state' => 'running').each(&:cancel)
      suspend
    end

    # Helper for creating sub plans
    def trigger(*args)
      if uses_concurrency_control
        world.plan_with_caller(self, *args)
      else
        world.trigger { world.plan_with_caller(self, *args) }
      end
    end

    def limit_concurrency_level(level)
      input[:concurrency_control] ||= {}
      input[:concurrency_control][:level] = ::Dynflow::Semaphores::Stateful.new(level).to_hash
    end

    def calculate_time_distribution(count)
      time = input[:concurrency_control][:time]
      unless time.nil? || time.is_a?(Hash)
        # Assume concurrency level 1 unless stated otherwise
        level = input[:concurrency_control].fetch(:level, {}).fetch(:free, 1)
        semaphore = ::Dynflow::Semaphores::Stateful.new(nil, level,
                                                        :interval => time.to_f / (count * level),
                                                        :time_span => time)
        input[:concurrency_control][:time] = semaphore.to_hash
      end
    end

    def distribute_over_time(time_span)
      input[:concurrency_control] ||= {}
      input[:concurrency_control][:time] = time_span
    end

    def wait_for_sub_plans(sub_plans)
      output.update(total_count: 0,
                    failed_count: 0,
                    success_count: 0,
                    pending_count: 0)

      planned, failed = sub_plans.partition(&:planned?)

      sub_plan_ids = (planned + failed).map(&:execution_plan_id)

      output[:total_count] = sub_plan_ids.size
      output[:failed_count] = failed.size
      output[:pending_count] = planned.size

      if planned.any?
        notify_on_finish(planned)
      else
        check_for_errors!
      end
    end

    def try_to_finish
      if done?
        check_for_errors!
        on_finish
        return true
      else
        return false
      end
    end

    def resume
      if sub_plans.all? { |sub_plan| sub_plan.error_in_plan? }
        initiate
      else
        recalculate_counts
        try_to_finish or fail "Some sub plans are still not finished"
      end
    end

    def sub_plans(filter = {})
      @sub_plans ||= world.persistence.find_execution_plans(filters: { 'caller_execution_plan_id' => execution_plan_id,
                                                                       'caller_action_id' => self.id }.merge(filter) )
    end

    def notify_on_finish(plans)
      suspend do |suspended_action|
        plans.each do |plan|
          plan.finished.on_completion! do |success, value|
            suspended_action << SubPlanFinished[plan.id, success && (value.result == :success)]
          end
        end
      end
    end

    def mark_as_done(plan_id, success)
      if success
        output[:success_count] += 1
      else
        output[:failed_count] += 1
      end
      output[:pending_count] -= 1
    end

    def done?
      if counts_set?
        output[:total_count] - output[:success_count] - output[:failed_count] <= 0
      else
        false
      end
    end

    def run_progress
      if counts_set? && output[:total_count] > 0
        (output[:success_count] + output[:failed_count]).to_f / output[:total_count]
      else
        0.1
      end
    end

    def recalculate_counts
      output.update(total_count: 0,
                    failed_count: 0,
                    success_count: 0,
                    pending_count: 0)
      sub_plans.each do |sub_plan|
        output[:total_count] += 1
        if sub_plan.state == :stopped
          if sub_plan.error?
            output[:failed_count] += 1
          else
            output[:success_count] += 1
          end
        else
          output[:pending_count] += 1
        end
      end
    end

    def counts_set?
      output[:total_count] && output[:success_count] && output[:failed_count] && output[:pending_count]
    end

    def check_for_errors!
      fail "A sub task failed" if output[:failed_count] > 0
    end

    def uses_concurrency_control
      @uses_concurrency_control = input.key? :concurrency_control
    end
  end
end
