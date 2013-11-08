module Dynflow
  module Stateful
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def states
        raise NotImplementedError
      end

      def state_transitions
        raise NotImplementedError
      end
    end

    def states
      self.class.states
    end

    def state_transitions
      self.class.state_transitions
    end

    attr_reader :state

    def state=(state)
      set_state state, false
    end

    def set_state(state, skip_transition_check)
      state = state.to_sym if state.is_a?(String) && states.map(&:to_s).include?(state)
      raise "unknown state #{state}" unless states.include? state
      unless self.state.nil? || skip_transition_check || state_transitions.fetch(self.state).include?(state)
        raise "invalid state transition #{self.state} >> #{state} in #{self}"
      end
      @state = state
    end
  end
end
