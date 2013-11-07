module Dynflow
  module Action::RunPhase

    def self.included(base)
      base.send(:include, Action::FlowPhase)
      base.attr_indifferent_access_hash :output
    end

    SUSPENDING = Object.new

    def execute(done = nil, *args)
      case state
      when :suspended
        self.state = :running
        save_state
        with_error_handling do
          update_progress done, *args
        end
        self.state = :suspended unless done

      when :running
        raise NotImplementedError, 'recovery after restart is not implemented'

      when :pending, :error
        raise unless done.nil? && args.empty?
        self.state = :running
        save_state
        with_error_handling do
          if catch(SUSPENDING) { run } == SUSPENDING
            self.state       = :suspended
            suspended_action = Action::Suspended.new(self)
            setup_suspend suspended_action
          end
        end

      else
        raise "wrong state #{state}"
      end
    end

    # DSL for run

    def suspend
      throw SUSPENDING, SUSPENDING
    end

    # TODO call suspend_setup after kill
    # FIXME handle after error
    # override
    # def suspend_setup(suspended_action)
    # end

    # override
    # def progress_update(done, *args)
    # end
  end
end
