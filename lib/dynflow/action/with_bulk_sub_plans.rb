module Dynflow
  module Action::WithBulkSubPlans
    include Dynflow::Action::Cancellable

    BATCH_SIZE=10

    # Should return a slice of size items starting from item with index from
    def entries(from, size)
      raise NotImplementedError
    end

    def total_count
      raise NotImplementedError
    end

    def current_batch
      start_position = output[:total_count]
      size = start_position + BATCH_SIZE > total_count ? total_count - start_position : BATCH_SIZE
      entries(start_position, size)
    end

    def done?
      super && total_count == output[:total_count]
    end

    def resume
      # TODO
      super
    end

    def run_progress
      if counts_set? && output[:total_count] > 0
        (output[:success_count] + output[:failed_count]).to_f / total_count
      else
        0.1
      end
    end

    def try_to_finish
      if can_spawn_next_batch?
        spawn_plans
      else
        super
      end
    end

    private

    def can_spawn_next_batch?
      total_count > output[:total_count]
    end

  end
end
