# frozen_string_literal: true

require_relative 'msgpack_migration_helper'

Sequel.migration do
  helper = MsgpackMigrationHelper.new({
    :dynflow_actions => [:data, :input, :output],
    :dynflow_coordinator_records => [:data],
    :dynflow_delayed_plans => [:serialized_args, :data],
    :dynflow_envelopes => [:data],
    :dynflow_execution_plans => [:run_flow, :finalize_flow, :execution_history, :step_ids],
    :dynflow_steps => [:error, :children],
    :dynflow_output_chunks => [:chunk]
  })

  up do
    helper.up(self)
  end

  down do
    helper.down(self)
  end
end
