# frozen_string_literal: true

Sequel.migration do
  up do
    type = database_type
    create_table(:dynflow_output_chunks) do
      primary_key :id

      column_properties = if type.to_s.include?('postgres')
                            {type: :uuid}
                          else
                            {type: String, size: 36, fixed: true, null: false}
                          end
      foreign_key :execution_plan_uuid, :dynflow_execution_plans, **column_properties
      index :execution_plan_uuid

      column :action_id, Integer, null: false
      foreign_key [:execution_plan_uuid, :action_id], :dynflow_actions,
        name: :dynflow_output_chunks_execution_plan_uuid_fkey1
      index [:execution_plan_uuid, :action_id]

      column :chunk, String, text: true
      column :kind, String
      column :timestamp, Time, null: false
    end
  end

  down do
    drop_table(:dynflow_output_chunks)
  end
end
