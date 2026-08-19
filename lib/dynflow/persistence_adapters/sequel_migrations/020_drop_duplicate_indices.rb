# frozen_string_literal: true

Sequel.migration do
  up do
    if indexes(:dynflow_actions).key?(:dynflow_actions_execution_plan_uuid_id_index)
      alter_table(:dynflow_actions) do
        drop_index [:execution_plan_uuid, :id]
      end
    end

    if indexes(:dynflow_execution_plans).key?(:dynflow_execution_plans_uuid_index)
      alter_table(:dynflow_execution_plans) do
        drop_index :uuid
      end
    end

    if indexes(:dynflow_steps).key?(:dynflow_steps_execution_plan_uuid_id_index)
      alter_table(:dynflow_steps) do
        drop_index [:execution_plan_uuid, :id]
      end
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
