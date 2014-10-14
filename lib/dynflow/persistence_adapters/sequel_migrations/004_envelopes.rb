Sequel.migration do
  change do
    create_table(:dynflow_envelopes) do
      primary_key :id
      foreign_key :receiver_id, :dynflow_worlds, type: String, size: 36, fixed: true
      index       :receiver_id
      column      :data, String, text: true
    end
  end
end
