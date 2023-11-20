# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:dynflow_delayed_plans) do
      add_column :serialized_kwargs, File
    end
  end
end
