module Dynflow
  module Action::Cancellable
    include Action::Polling
    Cancel = Algebrick.atom

    def run(event = nil)
      if Cancel === event
        cancel!
      else
        super event
      end
    end

    def cancel!
      NotImplementedError
    end
  end
end
