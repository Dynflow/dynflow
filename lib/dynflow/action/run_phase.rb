module Dynflow
  module Action::RunPhase

    def self.included(base)
      base.send(:include, Action::FlowPhase)
      base.attr_indifferent_access_hash :output
    end

    SUSPEND = Object.new

    def execute(event)
      action_logger.debug "step #{execution_plan_id}:#{@step.id} got event #{event}" if event
      case
      when state == :running
        raise NotImplementedError, 'recovery after restart is not implemented'

      when [:pending, :error, :suspended].include?(state)
        self.state = :running
        save_state
        with_error_handling do
          result = catch(SUSPEND) { event ? run(event) : run }
          if result == SUSPEND
            self.state = :suspended
          end
        end

      else
        raise "wrong state #{state} when event:#{event}"
      end
    end

    # DSL for run

    def suspend(&block)
      # TODO can Work::Event run before Work::Step is done? Check!
      block.call Action::Suspended.new self if block
      throw SUSPEND, SUSPEND
    end
  end
end
