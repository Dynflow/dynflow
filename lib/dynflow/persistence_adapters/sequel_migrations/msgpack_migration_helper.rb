# frozen_string_literal: true

require 'json'
require 'msgpack'

class MsgpackMigrationHelper
  def initialize(tables)
    @tables = tables
  end

  def up(migration)
    @tables.each do |table, columns|
      new_columns = columns.map { |c| "#{c}_blob" }

      migrate_table migration, table, columns, new_columns, File do |data|
        ::Sequel.blob(MessagePack.pack(JSON.parse(data)))
      end
    end
  end

  def down(migration)
    @tables.each do |table, columns|
      new_columns = columns.map { |c| c + '_text' }
      migrate_table migration, table, columns, new_columns, String do |data|
        JSON.dump(MessagePack.unpack(data))
      end
    end
  end

  private

  def migrate_table(migration, table, from_names, to_names, new_type)
    migration.alter_table(table) do
      to_names.each do |new|
        add_column new, new_type
      end
    end

    relevant_columns = table_pkeys(table) | from_names

    migration.from(table).select(*relevant_columns).each do |row|
      update = from_names.zip(to_names).reduce({}) do |acc, (from, to)|
        row[from].nil? ? acc : acc.merge(to => yield(row[from]))
      end
      next if update.empty?
      migration.from(table).where(conditions_for_row(table, row)).update(update)
    end

    from_names.zip(to_names).each do |old, new|
      migration.alter_table(table) do
        drop_column old
      end

      if migration.database_type == :mysql
        type = new_type == File ? 'blob' : 'mediumtext'
        run "ALTER TABLE #{table} CHANGE COLUMN `#{new}` `#{old}` #{type};"
      else
        migration.rename_column table, new, old
      end
    end
  end

  def conditions_for_row(table, row)
    row.slice(*table_pkeys(table))
  end

  def table_pkeys(table)
    case table
    when :dynflow_execution_plans
      [:uuid]
    when :dynflow_actions, :dynflow_steps
      [:execution_plan_uuid, :id]
    when :dynflow_coordinator_records
      [:id, :class]
    when :dynflow_delayed_plans
      [:execution_plan_uuid]
    when :dynflow_envelopes
      [:id]
    when :dynflow_output_chunks
      [:id]
    else
      raise "Unknown table '#{table}'"
    end
  end
end
