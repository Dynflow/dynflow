# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:dynflow_execution_plans) do
      long_text_type = @db.database_type == :mysql ? :mediumtext : String

      add_column :class, String

      add_column :run_flow, long_text_type
      add_column :finalize_flow, long_text_type
      add_column :execution_history, long_text_type

      # These could be removed in the future because an action can have at most one of each
      #   and each belongs to an action
      add_column :root_plan_step_id, Integer
      add_column :step_ids, long_text_type
    end
  end
end
