Sequel.migration do
  change do
    create_table(:dynflow_coordinator_records) do
      column :id, String
      column :class, String
      primary_key [:id, :class]
      index :class
      column :owner_id, String
      index :owner_id
      column :data, String, text: true
    end
  end
end

