Sequel.migration do
  up do
    create_table(:dynflow_execution_plans) do
      column :uuid, String, primary_key: true, size: 36, fixed: true
      index :uuid, :unique => true

      column :data, String, text: true

      column :state, String
      column :result, String
      column :started_at, Time
      column :ended_at, Time
      column :real_time, Float
      column :execution_time, Float
    end

    create_table(:dynflow_actions) do
      foreign_key :execution_plan_uuid, :dynflow_execution_plans, type: String, size: 36, fixed: true
      index :execution_plan_uuid
      column :id, Fixnum
      primary_key [:execution_plan_uuid, :id]
      index [:execution_plan_uuid, :id], :unique => true

      column :data, String, text: true
    end

    create_table(:dynflow_steps) do
      foreign_key :execution_plan_uuid, :dynflow_execution_plans, type: String, size: 36, fixed: true
      index :execution_plan_uuid
      column :id, Fixnum
      primary_key [:execution_plan_uuid, :id]
      index [:execution_plan_uuid, :id], :unique => true
      column :action_id, Fixnum
      foreign_key [:execution_plan_uuid, :action_id], :dynflow_actions
      index [:execution_plan_uuid, :action_id]

      column :data, String, text: true

      column :state, String
      column :started_at, Time
      column :ended_at, Time
      column :real_time, Float
      column :execution_time, Float
    end
  end

  down do
    drop_table(:dynflow_steps)
    drop_table(:dynflow_actions)
    drop_table(:dynflow_execution_plans)
  end
end
