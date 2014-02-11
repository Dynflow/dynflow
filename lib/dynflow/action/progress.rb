module Dynflow

  # Methods for specifying the progress of the action
  # the +*_progress+ methods should return number in 0..1.
  # The weight is there to increase/decrease the portion of this task
  # in the context of other tasks in execution plan. Normal action has
  # weight 1.
  #
  # The +*_progress+ is run only when the action is in running/suspend state. Otherwise
  # the progress is 1 for success/skipped actions and 0 for errorneous ones.
  module Action::Progress

    def run_progress
      0.5
    end

    def run_progress_weight
      1
    end

    def finalize_progress
      0.5
    end

    def finalize_progress_weight
      1
    end

    # this method is not intended to be overriden. Use +{run, finalize}_progress+
    # variants instead
    def progress_done
      case self.state
      when :success, :skipped
        1
      when :running, :suspended
        case phase
        when Action::Run
          run_progress
        when Action::Finalize
          finalize_progress
        else
          raise 'Calculating progress for this phase is not supported'
        end
      else
        0
      end
    end

    def progress_weight
      case phase
      when Action::Run
        run_progress_weight
      when Action::Finalize
        finalize_progress_weight
      else
        raise 'Calculating progress for this phase is not supported'
      end
    end

  end
end

