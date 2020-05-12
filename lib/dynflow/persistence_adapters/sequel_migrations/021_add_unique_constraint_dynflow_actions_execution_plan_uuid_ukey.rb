# frozen_string_literal: true
Sequel.migration do
  up do
    alter_table :dynflow_actions do
      add_unique_constraint [:execution_plan_uuid], name: :dynflow_actions_execution_plan_uuid_ukey
    end
  end

  down do
    alter_table :dynflow_actions do
      drop_constraint :dynflow_actions_execution_plan_uuid_ukey
    end
  end
end
