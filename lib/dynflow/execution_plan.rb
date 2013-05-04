require 'forwardable'

module Dynflow
  class ExecutionPlan

    attr_reader :run_steps, :finalize_steps

    # allows storing and reloading the execution plan to something
    # more persistent than memory
    attr_accessor :persistence
    # one of [new, running, paused, aborted, finished]
    attr_accessor :status

    extend Forwardable

    def initialize(run_steps = [], finalize_steps = [])
      @run_steps = run_steps
      @finalize_steps = finalize_steps
      @status = 'new'
    end

    def <<(action)
      run_step = Step::Run.new(action)
      @run_steps << run_step if action.respond_to? :run
      @finalize_steps << Step::Finalize.new(run_step) if action.respond_to? :finalize
    end

    def concat(other)
      self.run_steps.concat(other.run_steps)
      self.finalize_steps.concat(other.finalize_steps)
    end

    # update the persistence based on the current status
    def persist
      # TODO: move to step
      return
      if @persistence
        @persistence.persist(self)
      end
    end

  end
end
