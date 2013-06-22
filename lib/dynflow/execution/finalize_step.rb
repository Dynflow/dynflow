module Dynflow
  class FinalizeStep < Dynflow::Step

    def initialize(run_step)
      # we want to have the steps separated:
      # not using the original action object
      @action_class = run_step.action_class
      self.status = 'pending' # default status
      if run_step.action_class.instance_methods.include?(:run)
        @data = {
          'input' => Reference.new(run_step, 'input'),
          'output' => Reference.new(run_step, 'output'),
        }
      else
        @data = run_step.data
      end
    end

  end
end
