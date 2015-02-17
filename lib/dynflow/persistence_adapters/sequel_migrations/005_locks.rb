Sequel.migration do
  change do
    create_table(:dynflow_locks) do
      column :id, String, primary_key: true
      column :world_id, String, size: 36, fixed: true
    end
  end
end
