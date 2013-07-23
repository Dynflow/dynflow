module Dynflow
  module Action::Running
    attr_reader :input, :output, :error

    def initialize(world, status, id, input)
      super world, status, id
      @input  = input
      @output = {}
      @error  = {}
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
