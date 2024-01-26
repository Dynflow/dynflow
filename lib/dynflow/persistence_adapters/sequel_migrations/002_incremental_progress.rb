# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:dynflow_steps) do
      add_column :progress_done, Float
      add_column :progress_weight, Float
    end
  end
end
