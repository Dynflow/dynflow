# frozen_string_literal: true

require_relative 'test_helper'
require 'ostruct'

module Dynflow
  describe 'persistence telemetry' do
    class RecordingTelemetryAdapter < TelemetryAdapters::Dummy
      attr_reader :measurements

      def initialize
        @measurements = []
      end

      def measure(name, tags = {})
        @measurements << [name, tags]
        yield
      end
    end

    it 'measures persistence calls' do
      adapter = RecordingTelemetryAdapter.new
      previous_adapter = Telemetry.instance
      Telemetry.set_adapter(adapter)

      persistence = Persistence.allocate
      persistence.instance_variable_set(:@world, OpenStruct.new(id: 'world-id'))
      persistence.instance_variable_set(:@adapter, Object.new.tap do |object|
        def object.find_execution_plans(_options)
          []
        end
      end)

      _(persistence.find_execution_plans({})).must_equal []
      _(adapter.measurements).must_equal [[:dynflow_persistence, { method: :find_execution_plans, world: 'world-id' }]]
    ensure
      Telemetry.set_adapter(previous_adapter)
    end
  end
end
