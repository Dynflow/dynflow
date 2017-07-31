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

    def initiate
      ping suspended_action
      super
    end

    def wait_for_sub_plans(sub_plans)
      increase_counts(sub_plans.count, 0)
      suspend
    end

    def resume
      if sub_plans.all? { |sub_plan| sub_plan.error_in_plan? }
        output[:resumed_count] ||= 0
        output[:resumed_count] += output[:failed_count]
        # We're starting over and need to reset the counts
        %w(total failed pending success).each { |key| output.delete("#{key}_count".to_sym) }
        initiate
      else
        if self.is_a?(::Dynflow::Action::WithBulkSubPlans) && can_spawn_next_batch?
          # Not everything was spawned
          ping suspended_action
          spawn_plans
          suspend
        else
          poll
        end
      end
    end

    def notify_on_finish(_sub_plans)
      suspend
    end

    def suspend_and_ping
      suspend { |suspended_action| ping suspended_action }
    end

    def ping(suspended_action)
      world.clock.ping suspended_action, REFRESH_INTERVAL, Poll
    end

    def recalculate_counts
      total      = sub_plans.count
      failed     = sub_plans('state' => %w(paused stopped), 'result' => 'error').count
      success    = sub_plans('state' => 'stopped', 'result' => 'success').count
      output.update(:total_count   => total - output.fetch(:resumed_count, 0),
                    :pending_count => 0,
                    :failed_count  => failed - output.fetch(:resumed_count, 0),
                    :success_count => success)
    end
  end
end
