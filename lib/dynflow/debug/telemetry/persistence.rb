# frozen_string_literal: true

module Dynflow
  module Debug
    module Telemetry
      module Persistence
        methods = [
          :load_action,
          :load_actions,
          :load_action_for_presentation,
          :load_actions_attributes,
          :save_action,
          :save_output_chunks,
          :load_output_chunks,
          :delete_output_chunks,
          :find_execution_plans,
          :find_execution_plan_statuses,
          :find_execution_plan_counts,
          :find_execution_plan_counts_after,
          :delete_execution_plans,
          :load_execution_plan,
          :save_execution_plan,
          :find_old_execution_plans,
          :find_execution_plan_dependencies,
          :find_blocked_execution_plans,
          :find_ready_delayed_plans,
          :delete_delayed_plans,
          :save_delayed_plan,
          :set_delayed_plan_frozen,
          :load_delayed_plan,
          :load_step,
          :load_steps,
          :save_step,
          :push_envelope,
          :pull_envelopes,
          :prune_envelopes,
          :prune_undeliverable_envelopes,
          :chain_execution_plan
        ]

        methods.each do |name|
          define_method(name) do |*args|
            Dynflow::Telemetry.measure(:dynflow_persistence, :method => name, :world => @world.id) { super(*args) }
          end
        end
      end
    end
  end
end

::Dynflow::Persistence.prepend ::Dynflow::Debug::Telemetry::Persistence
