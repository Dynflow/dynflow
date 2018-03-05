Sequel.migration do
  change do
    alter_table(:dynflow_steps) do
      add_column :class, String
      add_column :error, @db.database_type == :mysql ? :mediumtext : String

      # These could be removed in the future because an action can have at most one of each
      #   and each belongs to an action
      add_column :action_class, String
      add_column :children, String
    end
  end
end
