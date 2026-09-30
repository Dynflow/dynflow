# frozen_string_literal: true

require_relative 'test_helper'

describe 'Sequel persistence migrations' do
  let(:db) { Sequel.connect('sqlite:/') }
  let(:migrations_path) { Dynflow::PersistenceAdapters::Sequel.migrations_path }

  after do
    db.disconnect
  end

  it 'tolerates duplicate indexes that are already absent' do
    Sequel::Migrator.run(db, migrations_path, table: 'dynflow_schema_info', target: 19)
    db.alter_table(:dynflow_actions) do
      drop_index [:execution_plan_uuid, :id]
    end

    Sequel::Migrator.run(db, migrations_path, table: 'dynflow_schema_info', target: 20)

    _(db.indexes(:dynflow_actions)).wont_include :dynflow_actions_execution_plan_uuid_id_index
    _(db.indexes(:dynflow_execution_plans)).wont_include :dynflow_execution_plans_uuid_index
    _(db.indexes(:dynflow_steps)).wont_include :dynflow_steps_execution_plan_uuid_id_index
  end
end
