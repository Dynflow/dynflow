require 'forwardable'

module Dynflow
  class ExecutionPlan

    class RunPlan
      attr_reader :steps

      def initialize(&block)
        @steps = []
        yield @steps if block_given?
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
      # sequences don't include concurrent actions. In other
      # words, the actions within a sequence are not marked for
      # concurrence even though they might be independent from each
      # other (having for example some common dependency/being common dependency
      # for some step)
      def add_if_satisfied(step, deps)
        if deps.empty?
          @steps << step
          return true
        end

        satisfying_indexes = deps.map { |dep| satisfying_index(dep) }.compact

        # all deps for the step are withing this plan
        if satisfying_indexes.size == deps.size
          sequence = merge_to_sequence(satisfying_indexes)
          sequence.steps << step
          return true
        end
        return false
      end

      private

      # index of a step that is able to satisfy the dependent step
      def satisfying_index(dependent_step)
        return @steps.index { |step| step.satisfying_step(dependent_step) }
      end

      def merge_to_sequence(step_indexes)
        step_indexes.sort!
        step_index = step_indexes.first
        sequence = convert_to_sequence(step_index)
        steps_or_sequences = step_indexes[1..-1].reverse.map do |index|
          @steps.delete_at(index)
        end.reverse

        steps_to_merge = steps_or_sequences.map do |step|
          case step
          when Step
            step
          when Sequence
            step.steps
          else
            raise NotImplementedError, "Don't know how to merge #{step} to sequence"
          end
        end.flatten
        sequence.steps.concat(steps_to_merge)
        return sequence
      end

      def convert_to_sequence(step_index)
        step = @steps[step_index]
        case step
        when Step
          sequence = Sequence.new
          sequence.steps << step
          @steps[step_index] = sequence
        when Sequence
          sequence = step
        else
          raise NotImplementedError, "Don't know how convert #{step} to sequence"
        end
        return sequence
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
