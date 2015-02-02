Sequel.migration do
  change do
    create_table(:dynflow_envelopes) do
      primary_key :id
      # we don't add a foreign key to worlds here as there might be an envelope created for the world
      # while the world gets terminated, and it would mess the whole thing up:
      # error on the world deletion because some envelopes arrived in the meantime
      # we still do our best to remove the envelopes if we can
      column :receiver_id, String, size: 36, fixed: true
      index       :receiver_id
      column      :data, String, text: true
    end
  end
end
