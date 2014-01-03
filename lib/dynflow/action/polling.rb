module Dynflow
  module Action::Polling

    Poll = Algebrick.atom

    def run(event = nil)
      case event
      when nil
        self.external_task = invoke_external_task
        suspend_and_ping
      when Poll
        self.external_task = poll_external_task
        suspend_and_ping unless done?
      else
        raise "unrecognized event #{event}"
      end
    end

    private

    def invoke_external_task
      raise NotImplementedError
    end

    def external_task=(external_task_data)
      raise NotImplementedError
    end

    def external_task
      raise NotImplementedError
    end

    def poll_external_task
      raise NotImplementedError
    end

    def done?
      raise NotImplementedError
    end

    def suspend_and_ping
      suspend { |suspended_action| world.clock.ping suspended_action, Time.now + poll_interval, Poll }
    end

    def poll_interval
      0.5
    end
  end
end
