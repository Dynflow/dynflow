Sequel.migration do
  change do
    create_table(:dynflow_worlds) do
      column :id, String, primary_key: true, size: 36, fixed: true
      index  :id, :unique => true
      column :executor, TrueClass
      index  :executor
    end
  end
end
