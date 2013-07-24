module Dynflow
  module Action::Running

    def self.included(base)
      base.extend(ClassMethods)
    end

    attr_reader :input, :output, :error

    def initialize(world, status, id, input, output = {}, error = {})
      super world, status, id
      @input  = is_kind_of! input, Hash
      @output = output
      @error  = error
    end

    def execute
      with_suspend do
        with_error_handling do
          run
        end
      end
    end

    def to_hash
      super.merge input:  input,
                  output: output,
                  error:  error
    end

    module ClassMethods
      def new_from_hash(world, status, action_id, hash)
        klass = hash[:class].constantize
        klass.running.new(world,
                          status,
                          action_id,
                          hash[:input],
                          hash[:output],
                          hash[:error])
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
