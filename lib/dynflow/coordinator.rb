require 'dynflow/coordinator_adapters'

module Dynflow
  class Coordinator

    class Lock < Serializable

      attr_reader :data

      include Algebrick::TypeCheck

      def initialize(*args)
        @data ||= {}
        @data = @data.merge(class: self.class.name).with_indifferent_access
      end

      def self.new_from_hash(hash)
        self.allocate.tap { |lock| lock.from_hash(hash) }
      end

      def self.constantize(name)
        super(name)
      rescue NameError
        # If we don't find the lock name, return the most generic version
        Lock
      end

      def from_hash(hash)
        @id        = hash[:id]
        @owner_id  = hash[:owner_id]
        @data      = hash
        @from_hash = true
      end

      def to_hash
        @data
      end

      def to_s
        "#{self.class.name}: #{id} by #{owner_id}"
      end

      def id
        @data[:id]
      end

      def owner_id
        @data[:owner_id]
      end

      # @api override
      # check to be performed before we try to acquire the lock
      def validate!
        raise "Can't acquire the lock after deserialization" if @from_hash
        Type! id,       String
        Type! owner_id, String
        Type! @data,     Hash
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
      lock.validate!
      adapter.acquire(lock)
      if block
        begin
          block.call
        ensure
          adapter.release(lock)
        end
      end
    end

    def release(lock)
      adapter.release(lock)
    end

    def release_by_owner(owner_id)
      find_locks(owner_id: owner_id).map { |lock| release(lock) }
    end

    def find_locks(filter_options)
      adapter.find_locks(filter_options).map do |lock_data|
        Lock.from_hash(lock_data)
      end
    end

  end
end
