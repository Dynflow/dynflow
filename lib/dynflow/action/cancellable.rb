# frozen_string_literal: true

module Dynflow
  module Action::Cancellable
    Cancel = Algebrick.atom
    Abort  = Algebrick.atom

    def run(event = nil)
      case event
      when Cancel
        cancel!
      when Abort
        abort!
      else
        super event
      end
    end

    def cancel!
      raise NotImplementedError
    end

    def abort!
      cancel!
    end
  end
end
