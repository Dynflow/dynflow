# frozen_string_literal: true

require 'multi_json'
require 'msgpack'

def table_pkeys(table)
  case table
  when :dynflow_actions, :dynflow_steps
    [:execution_plan_uuid, :id]
  when :dynflow_coordinator_records
    [:id, :class]
  when :dynflow_delayed_plans
    [:execution_plan_uuid]
  when :dynflow_envelopes
    [:id]
  when
    [:uuid]
  end
end

def conditions_for_row(table, row)
  row.slice(*table_pkeys(table))
end

def migrate_table(table, from_names, to_names, new_type)
  alter_table(table) do
    to_names.each do |new|
      add_column new, new_type
    end
  end

  relevant_columns = table_pkeys(table) | from_names

  from(table).select(*relevant_columns).each do |row|
    update = from_names.zip(to_names).reduce({}) do |acc, (from, to)|
      row[from].nil? ? acc : acc.merge(to => yield(row[from]))
    end
    next if update.empty?
    from(table).where(conditions_for_row(table, row)).update(update)
  end

  from_names.zip(to_names).each do |old, new|
    alter_table(table) do
      drop_column old
    end

    if database_type == :mysql
      type = new_type == File ? 'blob' : 'mediumtext'
      run "ALTER TABLE #{table} CHANGE COLUMN `#{new}` `#{old}` #{type};"
    else
      rename_column table, new, old
    end
  end
end

Sequel.migration do

  TABLES = {
    :dynflow_actions => [:data, :input, :output],
    :dynflow_coordinator_records => [:data],
    :dynflow_delayed_plans => [:serialized_args, :data],
    :dynflow_envelopes => [:data],
    :dynflow_execution_plans => [:run_flow, :finalize_flow, :execution_history, :step_ids],
    :dynflow_steps => [:error, :children]
  }

  up do
    TABLES.each do |table, columns|
      new_columns = columns.map { |c| "#{c}_blob" }

      migrate_table table, columns, new_columns, File do |data|
        ::Sequel.blob(MessagePack.pack(MultiJson.load(data)))
      end
    end
  end

  down do
    TABLES.each do |table, columns|
      new_columns = columns.map { |c| c + '_text' }
      migrate_table table, columns, new_columns, String do |data|
        MultiJson.dump(MessagePack.unpack(data))
      end
    end
  end
end
