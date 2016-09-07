Sequel.migration do
  affected_tables = [:dynflow_actions, :dynflow_coordinator_records, :dynflow_delayed_plans,
                     :dynflow_envelopes, :dynflow_execution_plans]
  up do
    affected_tables.each do |table|
      alter_table(table) do
        if @db.database_type == :mysql
          set_column_type :data, :mediumtext
        end
      end
    end
  end

  down do
    affected_tables.each do |table|
      alter_table(table) do
        if @db.database_type == :mysql
          set_column_type :data, :text
        end
      end
    end
  end
end

