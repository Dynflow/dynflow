# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:dynflow_delayed_plans) do
      add_column :frozen, :boolean
    end
    self[:dynflow_delayed_plans].update(:frozen => false)
  end
end
