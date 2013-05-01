require 'forwardable'

module Dynflow
  class ExecutionPlan

    attr_reader :actions

    # allows storing and reloading the execution plan to something
    # more persistent than memory
    attr_accessor :persistence

    extend Forwardable

    def_delegators :actions, :'<<'

    def initialize(actions = [])
      @actions = actions
    end

    def concat(other)
      self.actions.concat(other.actions)
    end

  end
end
