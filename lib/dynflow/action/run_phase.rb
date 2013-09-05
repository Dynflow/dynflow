module Dynflow
  module Action::RunPhase

    def self.included(base)
      base.send(:include, Action::FlowPhase)
    end

    def execute
      with_error_handling do
        run
      end
    end

    # DSL for run

    # TODO use throw/catch to unwind the stack, accept block
    # example: suspend { |suspended_action| PollingService.wait_for_task(suspended_action, input[:external_task_id]) }
    def suspend
      self.state = :suspended
      return Action::Suspended.new(self)
    end

    # TODO unify under execute
    # https://github.com/iNecas/dynflow/pull/27#discussion_r6149190
    def __resume__(method, *args)
      with_error_handling do
        self.state = :pending
        self.send(method, *args)
      end
    end

    # TODO update_progress(done, *args)
    # same api on world
    # replaces #resume
  end
end
