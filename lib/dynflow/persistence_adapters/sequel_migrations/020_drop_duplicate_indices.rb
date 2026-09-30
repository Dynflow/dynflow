# frozen_string_literal: true

Sequel.migration do
  up do
    [
      [:dynflow_actions, [:execution_plan_uuid, :id]],
      [:dynflow_execution_plans, :uuid],
      [:dynflow_steps, [:execution_plan_uuid, :id]],
    ].each do |table, columns|
      index_name = default_index_name(table, Array(columns)).to_sym
      next unless indexes(table).key?(index_name)

      alter_table(table) do
        drop_index columns
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
