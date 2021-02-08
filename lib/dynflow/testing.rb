# frozen_string_literal: true
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

    include Assertions
    include Factories
  end
end
