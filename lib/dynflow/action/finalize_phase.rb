module Dynflow
  module Action::FinalizePhase

    def self.included(base)
      base.send(:include, Action::FlowPhase)
      base.send(:attr_reader, :output)
    end

    def execute
      self.state = :running
      save_state
      with_error_handling do
        world.middleware.execute(:finalize, self) do
          finalize
        end
      end
    end

  end
end
