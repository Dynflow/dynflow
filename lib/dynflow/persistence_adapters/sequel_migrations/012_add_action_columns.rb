Sequel.migration do
  change do
    alter_table(:dynflow_actions) do
      add_column :class, String
      add_column :input, String
      add_column :output, String

      # These could be removed in the future because an action can have at most one of each
      #   and each belongs to an action
      add_column :plan_step_id, Integer
      add_column :run_step_id, Integer
      add_column :finalize_step_id, Integer
    end
  end
end
