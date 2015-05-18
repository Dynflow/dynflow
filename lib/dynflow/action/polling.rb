require 'dynflow/action/timeouts'

module Dynflow
  module Action::Polling

    def self.included(base)
      base.send :include, Action::Timeouts
    end

    Poll = Algebrick.atom

    def run(event = nil)
      case event
      when nil
        if external_task
          resume_external_action
        else
          initiate_external_action
        end
      when Poll
        poll_external_task_with_rescue
      when Action::Timeouts::Timeout
        process_timeout
        suspend
      else
        raise "unrecognized event #{event}"
      end
      done? ? on_finish : suspend_and_ping
    end

    def done?
      raise NotImplementedError
    end

    def invoke_external_task
      raise NotImplementedError
    end

    def poll_external_task
      raise NotImplementedError
    end

    def on_finish
    end

    # External task data. It should return nil when the task has not
    # been triggered yet.
    def external_task
      output[:task]
    end

    def external_task=(external_task_data)
      output[:task] = external_task_data
    end

    # What is the trend in waiting for next polling event. It allows
    # to strart with frequent polling, but slow down once it's clear this
    # task will take some time: the idea is we don't care that much in finishing
    # few seconds sooner, when the task takes orders of minutes/hours. It allows
    # not overwhelming the backend-servers with useless requests.
    # By default, it switches to next interval after +attempts_before_next_interval+ number
    # of attempts
    def poll_intervals
      [0.5, 1, 2, 4, 8, 16]
    end

    def attempts_before_next_interval
      5
    end

    # Returns the time to wait between two polling intervals.
    def poll_interval
      interval_level = poll_attempts[:total]/attempts_before_next_interval
      poll_intervals[interval_level] || poll_intervals.last
    end

    # How man times in row should we retry the polling before giving up
    def poll_max_retries
      3
    end

    def initiate_external_action
      self.external_task = invoke_external_task
    end

    def resume_external_action
      poll_external_task_with_rescue
    rescue
      initiate_external_action
    end

    def suspend_and_ping
      suspend { |suspended_action| world.clock.ping suspended_action, poll_interval, Poll }
    end

    def poll_external_task_with_rescue
      poll_attempts[:total] += 1
      self.external_task = poll_external_task
      poll_attempts[:failed] = 0
    rescue => error
      poll_attempts[:failed] += 1
      rescue_external_task(error)
    end

    def poll_attempts
      output[:poll_attempts] ||= { total: 0, failed: 0 }
    end

    def rescue_external_task(error)
      if poll_attempts[:failed] < poll_max_retries
        action_logger.warn("Polling failed, attempt no. #{poll_attempts[:failed]}, retrying in #{poll_interval}")
        action_logger.warn(error)
      else
        raise error
      end
    end

  end
end
