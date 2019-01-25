Sequel.migration do
  change do
    alter_table(:dynflow_execution_plans) do
      add_column :rescue_plan_id, :uuid
      add_column :rescued_plan_id, :uuid
    end
  end
end
