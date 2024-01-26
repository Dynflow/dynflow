# frozen_string_literal: true
helper = Module.new do
  def to_uuid(table_name, column_name)
    set_column_type(table_name, column_name, :uuid, :using => "#{column_name}::uuid")
  end

  def from_uuid(table_name, column_name)
    set_column_type table_name, column_name, String, primary_key: true, size: 36, fixed: true
  end

  def with_foreign_key_recreation(&block)
    # Drop the foreign key constraints so we can change the column type
    alter_table :dynflow_actions do
      drop_foreign_key [:execution_plan_uuid]
    end
    alter_table :dynflow_steps do
      drop_foreign_key [:execution_plan_uuid]
      drop_foreign_key [:execution_plan_uuid, :action_id], :name => :dynflow_steps_execution_plan_uuid_fkey1
    end
    alter_table :dynflow_delayed_plans do
      drop_foreign_key [:execution_plan_uuid]
    end

    block.call

    # Recreat the foreign key constraints as they were before
    alter_table :dynflow_actions do
      add_foreign_key [:execution_plan_uuid], :dynflow_execution_plans
    end
    alter_table :dynflow_steps do
      add_foreign_key [:execution_plan_uuid], :dynflow_execution_plans
      add_foreign_key [:execution_plan_uuid, :action_id], :dynflow_actions,
        :name => :dynflow_steps_execution_plan_uuid_fkey1
    end
    alter_table :dynflow_delayed_plans do
      add_foreign_key [:execution_plan_uuid], :dynflow_execution_plans,
        :name => :dynflow_scheduled_plans_execution_plan_uuid_fkey
    end
  end
end

Sequel.migration do
  up do
    if database_type.to_s.include?('postgres')
      Sequel::Postgres::Database.include helper

      with_foreign_key_recreation do
        to_uuid :dynflow_execution_plans, :uuid
        to_uuid :dynflow_actions,         :execution_plan_uuid
        to_uuid :dynflow_steps,           :execution_plan_uuid
        to_uuid :dynflow_delayed_plans,   :execution_plan_uuid
      end
    end
  end

  down do
    if database_type.to_s.include?('postgres')
      Sequel::Postgres::Database.include helper

      with_foreign_key_recreation do
        from_uuid :dynflow_execution_plans, :uuid
        from_uuid :dynflow_actions,         :execution_plan_uuid
        from_uuid :dynflow_steps,           :execution_plan_uuid
        from_uuid :dynflow_delayed_plans,   :execution_plan_uuid
      end
    end
  end
end
