module Dynflow
  module Action::RunPhase

    def self.included(base)
      base.extend(ClassMethods)
      base.attr_indifferent_access_hash :input, :output
    end

    def initialize(attributes, world)
      super attributes, world
      run_step_id || raise(ArgumentError, 'missing run_step_id')

      self.input  = attributes[:input]
      self.output = attributes[:output] || {}
    end

    def execute
      #with_suspend do
      with_error_handling do
        run
      end
      #end
    end

    def to_hash
      super.merge input:  input,
                  output: output
    end

    module ClassMethods
      def new_from_hash(hash, state, run_step_id, world)
        klass = hash[:class].constantize
        klass.run_phase.new(hash.merge(state: state, run_step_id: run_step_id), world)
      end
    end

    # DSL for run

    #def suspend
    #  throw :suspend_action
    #end
    #
    #private
    #
    #def with_suspend(&block)
    #  suspended = true
    #  catch :suspend_action do
    #    block.call
    #    suspended = false
    #  end
    #  if suspended
    #    # TODO suspend
    #  end
    #end
  end
end
