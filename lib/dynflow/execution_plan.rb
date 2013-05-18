require 'forwardable'

module Dynflow
  class ExecutionPlan

    class RunPlan
      attr_reader :steps

      def initialize
        @steps = []
      end

      def add_if_satisfied(step, deps)
        raise NotImplementedError, "Abstract method"
      end
    end

    class Concurrence < RunPlan

      # if some step in steps satisfies all the deps (set of steps),
      # add the step in argument into a sequence with this satisfying
      # step.
      #
      # Limitation: for now, we can't handle more concurrent steps
      # satisfying deps for one step.
      # Also, sequences don't include concurrent actions. In other
      # words, the actions within a sequence are not marked for
      # concurrence even though they might be independent from each
      # other (having some common dependency/being common dependency
      # for some step)
      def add_if_satisfied(step, deps)
        if deps.empty?
          @steps << step
          return true
        end

        satisfying_indexes = deps.map { |dep| satisfying_index(dep) }.compact

        # all deps for the step are withing this plan
        if satisfying_indexes.size == deps.size
          if satisfying_indexes.uniq.size > 1
            raise NotImplementedError, "Merging more steps into sequence is not implemented for now"
          else
            satisfying_index = satisfying_indexes.first
            satisfying_step = @steps[satisfying_index]
            case satisfying_step
            when Step
              sequence = Sequence.new
              sequence.steps << satisfying_step
              @steps[satisfying_index] = sequence
            when Sequence
              sequence = satisfying_step
            else
              raise NotImplementedError, "Don't know how to add depending step to #{satisfying_step}"
            end

            sequence.steps << step
            return true
          end
        end
        return false
      end

      # index of a step that is able to satisfy the dependent step
      def satisfying_index(dependent_step)
        return @steps.index { |step| step.satisfying_step(dependent_step) }
      end

    end

    class Sequence < RunPlan

      def satisfying_step(dependent_step)
        if @steps.any? { |step| step.satisfying_step(dependent_step) }
          return self
        end
      end

    end

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

    def run_plan
      dep_tree = self.run_steps.reduce([]) do |dep_tree, step|
        dep_tree << [step, step.dependencies]
      end

      run_plan = Concurrence.new

      something_deleted = true
      while something_deleted
        something_deleted = false
        satisfied_steps = dep_tree.delete_if do |step, deps|
          if run_plan.add_if_satisfied(step, deps)
            something_deleted = true
          end
        end
      end

      if dep_tree.any?
        raise "Unresolved dependencies: #{dep_tree.inspect}"
      end

      return run_plan
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
