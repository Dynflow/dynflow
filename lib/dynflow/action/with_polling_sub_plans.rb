module Dynflow
  module Action::WithPollingSubPlans

    Poll = Algebrick.atom

    def run(event = nil)
      case event
      when Poll
        poll
      else
        super
      end
    end

    def poll
      recalculate_counts
      try_to_finish || suspend_and_ping
    end

    def wait_for_sub_plans(_sub_plans)
      poll
    end

    def notify_on_finish(_sub_plans)
      suspend_and_ping
    end

    def suspend_and_ping
      suspend do |suspended_action|
        world.clock.ping suspended_action, 10, Poll
      end
    end

    def recalculate_counts
      total = sub_plans.count
      @sub_plans = nil
      failed = sub_plans('state' => 'stopped', 'result' => 'error').count
      @sub_plans = nil
      success = sub_plans('state' => 'stopped', 'result' => 'success').count
      output.update(:total_count => total,
                    :pending_count => 0,
                    :failed_count => failed,
                    :success_count => success)
    end
  end
end
