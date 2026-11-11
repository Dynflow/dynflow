# frozen_string_literal: true

class TestExecutionLog
  include Enumerable

  def initialize
    @log = []
  end

  def <<(action)
    @log << [action.class, action.input]
  end

  def log
    @log
  end

  def each(&block)
    @log.each(&block)
  end

  def size
    @log.size
  end

  def self.setup
    @run = new
    @finalize = new
  end

  def self.teardown
    @run = nil
    @finalize = nil
  end

  def self.run
    @run || []
  end

  def self.finalize
    @finalize || []
  end
end
