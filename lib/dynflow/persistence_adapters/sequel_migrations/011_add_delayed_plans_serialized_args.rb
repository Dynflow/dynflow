Sequel.migration do
  change do
    alter_table(:dynflow_delayed_plans) do
      add_column :serialized_args, String
    end
  end
end
