module Dynflow

  # Methods for specifying the progress of the action
  # the +*_progress_done+ methods should return number in 0..100.
  # The weight is there to increase/decrease the portion of this task
  # in the context of other tasks in execution plan. Normal action has
  # weight 1.
  #
  # The +*_progress_done+ is run only when the action is in running/suspend state. Otherwise
  # the progress is 100 for success/skipped actions and 0 for errorneous ones.
  module Action::Progress

    def run_progress_done
      50
    end

    def run_progress_weight
      1
    end

    def finalize_progress_done
      50
    end

    def finalize_progress_weight
      1
    end

    # this method is not intended to be overriden. Use +{run, finalize}_progress_done+
    # variants instead
    def progress_done
      case self.state
      when :success, :skipped
        100
      when :running, :suspended
        case self
        when Action::RunPhase
          run_progress_done
        when Action::FinalizePhase
          finalize_progress_done
        else
          raise "Calculating progress for this phase is not supported"
        end
      else
        0
      end
    end

    def progress_weight
      case self
      when Action::RunPhase
        run_progress_weight
      when Action::FinalizePhase
        finalize_progress_weight
      else
        raise "Calculating progress for this phase is not supported"
      end
    end

  end
end

