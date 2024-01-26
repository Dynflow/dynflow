# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:dynflow_execution_plans) do
      add_column :label, String
    end
  end
end
