require 'dynflow/coordinator_adapters'

module Dynflow
  class Coordinator

    include Algebrick::TypeCheck

    class DuplicateRecordError < Dynflow::Error
      attr_reader :record

      def initialize(record)
        @record = record
        super("record #{record} already exists")
      end
    end

    class LockError < Dynflow::Error
      attr_reader :lock

      def initialize(lock)
        @lock = lock
        super("Unable to acquire lock #{lock}")
      end
    end

    class Record < Serializable
      attr_reader :data

      include Algebrick::TypeCheck

      def self.new_from_hash(hash)
        self.allocate.tap { |record| record.from_hash(hash) }
      end

      def self.constantize(name)
        Serializable.constantize(name)
      rescue NameError
        # If we don't find the lock name, return the most generic version
        Record
      end

      def initialize(*args)
        @data ||= {}
        @data = @data.merge(class: self.class.name).with_indifferent_access
      end

      def from_hash(hash)
        @data      = hash
        @from_hash = true
      end

      def to_hash
        @data
      end

      def id
        @data[:id]
      end

      # @api override
      # check to be performed before we try to acquire the lock
      def validate!
        Type! id,       String
        Type! @data,     Hash
      end

      def to_s
        "#{self.class.name}: #{id} by #{owner_id}"
      end
    end

    class Lock < Record
      def self.constantize(name)
        Serializable.constantize(name)
      rescue NameError
        # If we don't find the lock name, return the most generic version
        Lock
      end

      def to_s
        "#{self.class.name}: #{id} by #{owner_id}"
      end

      def owner_id
        @data[:owner_id]
      end

      # @api override
      # check to be performed before we try to acquire the lock
      def validate!
        super
        raise "Can't acquire the lock after deserialization" if @from_hash
        Type! owner_id, String
      end
    end

    class LockByWorld < Lock
      def initialize(world)
        super
        @world = world
        @data.merge!(owner_id: "world:#{world.id}",  world_id: world.id)
      end

      def validate!
        super
        raise Errors::InactiveWorldError.new(@world) if @world.terminating?
      end

      def world_id
        @data[:world_id]
      end

    end

    class WorldInvalidationLock < LockByWorld
      def initialize(world, invalidated_world)
        super(world)
        @data[:id] = "world-invalidation:#{invalidated_world.id}"
      end
    end

    class ConsistencyCheckLock < LockByWorld
      def initialize(*args)
        super
        @data[:id] = "consistency-check"
      end
    end

    class ExecutionLock < LockByWorld
      def initialize(world, execution_plan_id, client_world_id, request_id)
        super(world)
        @data.merge!(id: "execution-plan:#{execution_plan_id}",
                     execution_plan_id: execution_plan_id,
                     client_world_id: client_world_id,
                     request_id: request_id)
      end

      # we need to store the following data in case of
      # invalidation of the lock from outside (after
      # the owner world terminated unexpectedly)
      def execution_plan_id
        @data[:execution_plan_id]
      end

      def client_world_id
        @data[:client_world_id]
      end

      def request_id
        @data[:request_id]
      end
    end

    attr_reader :adapter

    def initialize(world, coordinator_adapter)
      @world   = world
      @adapter = coordinator_adapter
    end

    def acquire(lock, &block)
      Type! lock, Lock
      lock.validate!
      adapter.create_record(lock)
      if block
        begin
          block.call
        ensure
          release(lock)
        end
      end
    rescue DuplicateRecordError => e
      raise LockError.new(e.record)
    end

    def release(lock)
      Type! lock, Lock
      adapter.delete_record(lock)
    end

    def release_by_owner(owner_id)
      find_locks(owner_id: owner_id).map { |lock| release(lock) }
    end

    def find_locks(filter_options)
      adapter.find_records(filter_options).map do |lock_data|
        Lock.from_hash(lock_data)
      end
    end

    def create_record(record)
      Type! record, Record
      adapter.create_record(record)
    end

    def delete_record(record)
      Type! record, Record
      adapter.delete_record(record)
    end

    def find_records(filter)
      adapter.find_records(filter).map do |record_data|
        Record.from_hash(record_data)
      end
    end
  end
end
