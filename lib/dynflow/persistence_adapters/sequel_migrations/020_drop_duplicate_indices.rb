# frozen_string_literal: true
Sequel.migration do
  up do
    alter_table(:dynflow_actions) do
      drop_index [:execution_plan_uuid, :id]
    end

    alter_table(:dynflow_execution_plans) do
      drop_index :uuid
    end

    alter_table(:dynflow_steps) do
      drop_index [:execution_plan_uuid, :id]
    end
  end

  down do
    alter_table(:dynflow_actions) do
      add_index [:execution_plan_uuid, :id], :unique => true
    end

    alter_table(:dynflow_execution_plans) do
      add_index :uuid, :unique => true
    end

    alter_table(:dynflow_steps) do
      add_index [:execution_plan_uuid, :id], :unique => true
    end
  end
end
