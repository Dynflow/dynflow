module Dynflow
  class PlanStep < Dynflow::Step

    def initialize(action)
      # we want to have the steps separated:
      # not using the original action object
      @action_class = action.class
      self.status = 'finished' # default status
      @data = {}
    end

  end
end
