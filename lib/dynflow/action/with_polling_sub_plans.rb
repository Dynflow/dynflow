module Dynflow
  module Action::WithPollingSubPlans

    REFRESH_INTERVAL = 10
    Poll = Algebrick.atom

    def run(event = nil)
      case event
      when Poll
        poll
      else
        super(event)
      end
    end

    def poll
      recalculate_counts
      try_to_finish || suspend_and_ping
    end

    def wait_for_sub_plans(sub_plans)
      increase_counts(sub_plans.count, 0)
      if is_a?(::Dynflow::Action::WithBulkSubPlans)
        suspend
      else
        poll
      end
    end

    def on_planning_finished
      poll
    end

    def resume
      if sub_plans.all? { |sub_plan| sub_plan.error_in_plan? }
        # We're starting over and need to reset the counts
        %w(total failed pending success).each { |key| output.delete("#{key}_count".to_sym) }
        initiate
      else
        if self.is_a?(::Dynflow::Actions::WithBulkSubPlans) && can_spawn_next_batch?
          spawn_plans
          suspend
        else
          poll
        end
      end
    end


    def notify_on_finish(_sub_plans)
      suspend_and_ping
    end

    def suspend_and_ping
      suspend do |suspended_action|
        world.clock.ping suspended_action, REFRESH_INTERVAL, Poll
      end
    end

    def recalculate_counts
      total      = sub_plans.count
      @sub_plans = nil # TODO:
      failed     = sub_plans('state' => 'stopped', 'result' => 'error').count
      @sub_plans = nil # TODO:
      success    = sub_plans('state' => 'stopped', 'result' => 'success').count
      output.update(:total_count => total,
                    :pending_count => 0,
                    :failed_count => failed,
                    :success_count => success)
    end
  end
end
