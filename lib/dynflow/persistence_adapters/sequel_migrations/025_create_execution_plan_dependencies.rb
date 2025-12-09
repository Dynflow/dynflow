# frozen_string_literal: true

Sequel.migration do
  up do
    type = database_type
    create_table(:dynflow_execution_plan_dependencies) do
      column_properties = if type.to_s.include?('postgres')
                            { type: :uuid }
                          else
                            { type: String, size: 36, fixed: true, null: false }
                          end
      foreign_key :execution_plan_uuid, :dynflow_execution_plans, on_delete: :cascade, **column_properties
      foreign_key :blocked_by_uuid, :dynflow_execution_plans, on_delete: :cascade, **column_properties
      index :blocked_by_uuid
      index :execution_plan_uuid
    end
  end

  down do
    drop_table(:dynflow_execution_plan_dependencies)
  end
end
