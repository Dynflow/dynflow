# frozen_string_literal: true

module Dynflow
  module Action::Timeouts
    Timeout = Algebrick.atom

    def process_timeout
      fail("Timeout exceeded.")
    end

    def schedule_timeout(seconds, optional: false)
      plan_event(Timeout, seconds, optional: optional)
    end
  end
end
