Sequel.migration do
  change do
    create_table(:dynflow_worlds) do
      column :id, String, primary_key: true, size: 36, fixed: true
      index  :id, :unique => true
      column :executor, TrueClass
      index  :executor
    end

    create_table(:dynflow_executor_allocations) do
      foreign_key :world_id, :dynflow_worlds, type: String, size: 36, fixed: true
      index :world_id
      foreign_key :execution_plan_id, :dynflow_execution_plans,
          type: String, size: 36, fixed: true
      index :execution_plan_id, :unique => true
      primary_key [:world_id, :execution_plan_id]
    end
  end
end
