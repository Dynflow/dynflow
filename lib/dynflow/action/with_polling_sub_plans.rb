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
      stopped = sub_plans(:state => :stopped).count
      output.update(:total_count => total,
                    :done_count => stopped)
    end

    def done?
      if output.key?(:total_count) && output.key?(:done_count)
        output[:total_count] == output[:done_count]
      else
        false
      end
    end
  end
end
