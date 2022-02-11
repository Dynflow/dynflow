# frozen_string_literal: true

require_relative 'msgpack_migration_helper'

Sequel.migration do
  helper = MsgpackMigrationHelper.new({
    :dynflow_execution_plans => [:data],
    :dynflow_steps => [:data]
  })

  up do
    helper.up(self)
  end

  down do
    helper.down(self)
  end
end
