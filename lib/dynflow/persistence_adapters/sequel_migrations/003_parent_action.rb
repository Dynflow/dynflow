# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:dynflow_actions) do
      add_column :caller_execution_plan_id, String, fixed: true, size: 36
      add_column :caller_action_id, Integer
      add_index [:caller_execution_plan_id, :caller_action_id]
    end
  end
end
