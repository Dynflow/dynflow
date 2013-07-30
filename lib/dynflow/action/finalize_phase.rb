module Dynflow
  module Action::FinalizePhase

    def self.included(base)
      base.send(:include, Action::FlowPhase)
    end

    def execute
      with_error_handling do
        finalize
      end
    end

  end
end
