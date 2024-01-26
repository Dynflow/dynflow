# frozen_string_literal: true

module Dynflow
  module Debug
    module Telemetry
      module Persistence
        methods = [
          :load_action,
          :load_actions,
          :load_action_for_presentation,
          :load_action,
          :load_actions,
          :load_action_for_presentation,
          :load_actions_attributes,
          :save_action,
          :find_execution_plans,
          :find_execution_plan_counts,
          :delete_execution_plans,
          :load_execution_plan,
          :save_execution_plan,
          :find_old_execution_plans,
          :find_past_delayed_plans,
          :delete_delayed_plans,
          :save_delayed_plan,
          :set_delayed_plan_frozen,
          :load_delayed_plan,
          :load_step,
          :load_steps,
          :save_step,
          :push_envelope,
          :pull_envelopes
        ]

        methods.each do |name|
          define_method(name) do |*args|
            Dynflow::Telemetry.measure(:dynflow_persistence, :method => name, :world => @world.id) { super *args }
          end
        end
      end
    end
  end
end

::Dynflow::Persistence.send(:prepend, ::Dynflow::Debug::Persistence)
