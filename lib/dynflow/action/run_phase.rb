module Dynflow
  module Action::RunPhase

    def self.included(base)
      base.send(:include, Action::FlowPhase)
      base.attr_indifferent_access_hash :output
    end

    SUSPEND = Object.new

    def execute(event)
      @world.logger.debug "step #{execution_plan_id}:#{@step.id} got event #{event}" if event
      case
      when state == :running
        raise NotImplementedError, 'recovery after restart is not implemented'

      when [:pending, :error, :suspended].include?(state)
        if [:pending, :error].include?(state) && event
          raise 'event can be processed only when in suspended state'
        end

        self.state = :running
        save_state
        with_error_handling do
          result = catch(SUSPEND) do
            args = []
            args << event if event
            world.middleware.execute(:run, self, *args) do |*new_args|
              run(*new_args)
            end
          end
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
      block.call Action::Suspended.new self if block
      throw SUSPEND, SUSPEND
    end
  end
end
