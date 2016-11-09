module Dynflow
  module Testing
    extend Algebrick::TypeCheck

    def self.logger_adapter
      @logger_adapter || LoggerAdapters::Simple.new($stdout, 1)
    end

    def self.logger_adapter=(adapter)
      Type! adapter, LoggerAdapters::Abstract
      @logger_adapter = adapter
    end

    def self.get_id
      @last_id ||= 0
      @last_id += 1
    end

    require 'dynflow/testing/mimic'
    require 'dynflow/testing/managed_clock'
    require 'dynflow/testing/dummy_world'
    require 'dynflow/testing/dummy_executor'
    require 'dynflow/testing/dummy_execution_plan'
    require 'dynflow/testing/dummy_step'
    require 'dynflow/testing/dummy_planned_action'
    require 'dynflow/testing/in_thread_executor'
    require 'dynflow/testing/in_thread_world'
    require 'dynflow/testing/assertions'
    require 'dynflow/testing/factories'

    include Assertions
    include Factories
  end
end
