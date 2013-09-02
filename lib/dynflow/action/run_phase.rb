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

    def suspend
      self.state = :suspended
      return Action::Suspended.new(self)
    end

    def __resume__(method, *args)
      with_error_handling do
        self.state = :pending
        self.send(method, *args)
      end
    end

  end
end
