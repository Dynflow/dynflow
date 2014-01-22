module Dynflow
  module Action::CancellablePolling
    include Action::Polling
    Cancel = Algebrick.atom

    def run(event = nil)
      if Cancel === event
        self.external_task = cancel_external_task
      else
        super event
      end
    end

    def cancel_external_task
      NotImplementedError
    end
  end
end
