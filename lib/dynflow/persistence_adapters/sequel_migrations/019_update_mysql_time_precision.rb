# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:dynflow_execution_plans) do
      if @db.database_type == :mysql
        set_column_type :started_at, 'datetime(3)'
        set_column_type :ended_at, 'datetime(3)'
      end
    end

    alter_table(:dynflow_steps) do
      if @db.database_type == :mysql
        set_column_type :started_at, 'datetime(3)'
        set_column_type :ended_at, 'datetime(3)'
      end
    end

    alter_table(:dynflow_delayed_plans) do
      if @db.database_type == :mysql
        set_column_type :start_at, 'datetime(3)'
        set_column_type :start_before, 'datetime(3)'
      end
    end
  end

  down do
    alter_table(:dynflow_steps) do
      if @db.database_type == :mysql
        set_column_type :started_at, Time
        set_column_type :ended_at, Time
      end
    end

    alter_table(:dynflow_steps) do
      if @db.database_type == :mysql
        set_column_type :started_at, Time
        set_column_type :ended_at, Time
      end
    end

    alter_table(:dynflow_delayed_plans) do
      if @db.database_type == :mysql
        set_column_type :start_at, Time
        set_column_type :start_before, Time
      end
    end
  end
end
