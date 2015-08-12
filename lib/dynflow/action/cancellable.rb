module Dynflow
  module Action::Cancellable
    Cancel = Algebrick.atom

    def run(event = nil)
      if Cancel === event
        cancel!
      else
        super event
      end
    end

    def cancel!
      raise NotImplementedError
    end
  end
end
