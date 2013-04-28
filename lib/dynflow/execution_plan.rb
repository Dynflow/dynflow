require 'forwardable'

module Dynflow
  class ExecutionPlan

    attr_reader :actions

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
