# frozen_string_literal: true

tables = [:dynflow_actions, :dynflow_delayed_plans, :dynflow_steps, :dynflow_output_chunks]
Sequel.migration do
  up do
    if database_type == :sqlite && Gem::Version.new(SQLite3::SQLITE_VERSION) <= Gem::Version.new('3.7.17')
      tables.each do |table|
        alter_table(table) { drop_foreign_key [:execution_plan_uuid] }
      end
    end
  end

  down do
    if database_type == :sqlite && Gem::Version.new(SQLite3::SQLITE_VERSION) <= Gem::Version.new('3.7.17')
      tables.each do |table|
        alter_table(table) { add_foreign_key [:execution_plan_uuid], :dynflow_execution_plans }
      end
    end
  end
end
