module Dynflow
  # A simple round-robin scheduling implementation used at various
  # places in Dynflow
  class RoundRobin
    def initialize
      @data   = []
      @cursor = 0
    end

    def add(item)
      @data.push item
      self
    end

    def delete(item)
      @data.delete item
      self
    end

    def next
      @cursor = 0 if @cursor > @data.size-1
      @data[@cursor]
    ensure
      @cursor += 1
    end

    def empty?
      @data.empty?
    end

    # the `add` and `delete` methods should be preferred, but
    # sometimes the list of things to iterate though can not be owned
    # by the round robin object itself
    attr_writer :data
  end
end

