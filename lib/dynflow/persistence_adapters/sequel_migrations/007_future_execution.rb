Sequel.migration do
  change do
    create_table(:dynflow_scheduled_plans) do
      foreign_key :execution_plan_uuid, :dynflow_execution_plans, type: String, size: 36, fixed: true
      index :execution_plan_uuid
      column :start_at, Time
      index :start_at
      column :start_before, Time
      column :data, String, text: true
      column :args_serializer, String
    end
  end
end
