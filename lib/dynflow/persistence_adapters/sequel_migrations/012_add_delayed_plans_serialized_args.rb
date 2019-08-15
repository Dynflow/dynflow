# frozen_string_literal: true
Sequel.migration do
  change do
    alter_table(:dynflow_delayed_plans) do
      long_text_type = @db.database_type == :mysql ? :mediumtext : String
      add_column :serialized_args, long_text_type
    end
  end
end
