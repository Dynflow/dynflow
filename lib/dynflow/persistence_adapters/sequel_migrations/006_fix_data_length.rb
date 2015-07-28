Sequel.migration do
  up do
    alter_table(:dynflow_steps) do
      if @db.database_type == :mysql
        set_column_type :data, :mediumtext
      end
    end
  end

  down do
    alter_table(:dynflow_steps) do
      if @db.database_type == :mysql
        set_column_type :data, :text
      end
    end
  end
end
