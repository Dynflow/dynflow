# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:dynflow_steps) do
      add_column :queue, String
    end
  end
end
