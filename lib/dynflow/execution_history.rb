module Dynflow
  class ExecutionHistory
    include Algebrick::TypeCheck
    include Enumerable

    Event = Algebrick.type do
      fields! time:     Integer,
              name:     String,
              world_id: type { variants String, NilClass }
    end

    module Event
      def inspect
        "#{Time.at(time).utc}: #{name}".tap { |s| s << " @ #{world_id}" if world_id }
      end
    end

    attr_reader :events

    def initialize(events = [])
      @events = (events || []).each { |e| Type! e, Event }
    end

    def each(&block)
      @events.each(&block)
    end

    def add(name, world_id = nil)
      @events << Event[Time.now.to_i, name, world_id]
    end

    def to_hash
      @events.map(&:to_hash)
    end

    def inspect
      "ExecutionHistory: #{ @events.inspect }"
    end

    def self.new_from_hash(value)
      value ||= [] # for compatibility with tasks before the
      # introduction of execution history
      self.new(value.map { |hash| Event[hash] })
    end
  end
end
