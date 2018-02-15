Sequel.migration do
  change do
    alter_table(:dynflow_execution_plans) do
      add_column :class, String

      add_column :run_flow, String
      add_column :finalize_flow, String
      add_column :execution_history, String

      # These could be removed in the future because an action can have at most one of each
      #   and each belongs to an action
      add_column :root_plan_step_id, Integer
      add_column :step_ids, String
    end
  end
end
