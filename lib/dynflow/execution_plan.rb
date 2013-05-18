require 'forwardable'

module Dynflow
  class ExecutionPlan

    attr_reader :plan_steps, :run_steps, :finalize_steps

    # allows storing and reloading the execution plan to something
    # more persistent than memory
    attr_accessor :persistence
    # one of [new, running, paused, aborted, finished]
    attr_accessor :status

    extend Forwardable

    def initialize(plan_steps = [], run_steps = [], finalize_steps = [])
      @plan_steps = plan_steps
      @run_steps = run_steps
      @finalize_steps = finalize_steps
      @status = 'new'
    end

    def steps
      self.plan_steps + self.run_steps + self.finalize_steps
    end

    def failed_steps
      self.steps.find_all { |step| step.status == 'error' }
    end

    def inspect_steps(steps = nil)
      steps ||= self.steps
      steps.map(&:inspect).join("\n")
    end

    def <<(step)
      case step
      when Step::Run then self.run_steps << step
      when Step::Finalize then self.finalize_steps << step
      else raise ArgumentError, 'Only Run or Finalize steps can be planned'
      end
    end

    def concat(other)
      self.plan_steps.concat(other.plan_steps)
      self.run_steps.concat(other.run_steps)
      self.finalize_steps.concat(other.finalize_steps)
      self.status = other.status
    end

    # update the persistence based on the current status
    def persist(include_steps = false)
      if @persistence
        @persistence.persist(self)

        if include_steps
          steps.each { |step| step.persist }
        end
      end
    end

  end
end
