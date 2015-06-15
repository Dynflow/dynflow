module Dynflow
  module Action::Timeouts
    Timeout = Algebrick.atom

    def process_timeout
      fail("Timeout exceeded.")
    end

    def schedule_timeout(seconds)
      world.clock.ping suspended_action, seconds, Timeout
    end
 end
end
