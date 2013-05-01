require 'forwardable'

module Dynflow
  class ExecutionPlan

    attr_reader :actions

    # allows storing and reloading the execution plan to something
    # more persistent than memory
    attr_accessor :persistence
    # one of [new, running, paused, aborted, finished]
    attr_accessor :status

    extend Forwardable

    def_delegators :actions, :'<<'

    def initialize(actions = [])
      @actions = actions
      @status = 'new'
    end

    def concat(other)
      self.actions.concat(other.actions)
    end

    # update the persistence based on the current status
    def persist
      if @persistence
        @persistence.persist(self)
      end
    end

  end
end
