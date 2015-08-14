Sequel.migration do
  change do
    rename_table(:dynflow_scheduled_plans, :dynflow_delayed_plans)
  end
end
