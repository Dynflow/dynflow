module Dynflow
  module Action::WithBulkSubPlans
    include Dynflow::Action::Cancellable

    BATCH_SIZE = 10

    # Should return a slice of size items starting from item with index from
    def batch(from, size)
      raise NotImplementedError
    end

    PlanNextBatch = Algebrick.atom

    def run(event = nil)
      if event === PlanNextBatch
        spawn_plans if can_spawn_next_batch?
        suspend
      else
        super
      end
    end

    # Should return the expected total count of tasks
    def total_count
      raise NotImplementedError
    end

    # Returns the items in the current batch
    def current_batch
      start_position = output[:total_count]
      size = start_position + batch_size > total_count ? total_count - start_position : batch_size
      batch(start_position, size)
    end

    def batch_size
      BATCH_SIZE
    end

    def done?
      # The action is done if the real total count equal to the expected total count and all of them
      #   are either successful or failed
      super && total_count == output[:total_count]
    end

    # The same logic as in Action::WithSubPlans, but calculated using the expected total count
    def run_progress
      if counts_set?
        (output[:success_count] + output[:failed_count]).to_f / total_count
      else
        0.1
      end
    end

    def spawn_plans
      super
    ensure
      suspended_action << PlanNextBatch
    end

    private

    def can_spawn_next_batch?
      total_count > output[:total_count]
    end

  end
end
