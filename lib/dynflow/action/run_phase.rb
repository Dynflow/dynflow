module Dynflow
  module Action::RunPhase

    def self.included(base)
      base.send(:include, Action::FlowPhase)
      base.attr_indifferent_access_hash :output
    end

    SUSPENDING = Object.new

    def execute(done = nil, *args)
      Match! done, true, false, nil
      doing_progress_update = !done.nil?

      case
      when state == :running
        raise NotImplementedError, 'recovery after restart is not implemented'

      when state == :suspended && doing_progress_update
        self.state = :running
        save_state
        with_error_handling do
          update_progress done, *args
        end
        self.state = :suspended unless done

      when [:pending, :error].include?(state) && !doing_progress_update
        self.state = :running
        save_state
        with_error_handling do
          if catch(SUSPENDING) { run } == SUSPENDING
            self.state       = :suspended
            suspended_action = Action::Suspended.new(self)
            setup_progress_updates suspended_action
          end
        end

      else
        raise "wrong state #{state} when doing_progress_update:#{doing_progress_update}"
      end
    end

    # DSL for run

    # TODO move everything to ProgressUpdater, including remote_task start
    def suspend
      throw SUSPENDING, SUSPENDING
    end

    # TODO call setup_progress_updates after kill
    # TODO call setup_progress_updates after resume
    # FIXME handle after error
    # override
    # def suspend_setup(suspended_action)
    # end

    # override
    # def progress_update(done, *args)
    # end
  end
end
