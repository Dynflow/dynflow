# frozen_string_literal: true

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
    class Calculate < Middleware
      def run(*args)
        with_progress_calculation(*args) do
          [action.run_progress, action.run_progress_weight]
        end
      end

      def finalize(*args)
        with_progress_calculation(*args) do
          [action.finalize_progress, action.finalize_progress_weight]
        end
      end

      protected

      def with_progress_calculation(*args)
        pass(*args)
      ensure
        begin
          action.calculated_progress = yield
        rescue => error
          # we don't want progress calculation to cause fail of the whole process
          # TODO: introduce post-execute state for handling issues with additional
          # calculations after the step is run
          action.action_logger.error('Error in progress calculation')
          action.action_logger.error(error)
        end
      end
    end

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

    attr_accessor :calculated_progress
  end
end

