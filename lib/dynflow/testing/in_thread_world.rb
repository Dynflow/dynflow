module Dynflow
  module Testing
    class InThreadWorld < Dynflow::World
      def self.test_world_config
        config                     = Dynflow::Config.new
        config.persistence_adapter = persistence_adapter
        config.logger_adapter      = logger_adapter
        config.coordinator_adapter = coordinator_adapter
        config.delayed_executor    = nil
        config.auto_rescue         = false
        config.auto_validity_check = false
        config.exit_on_terminate   = false
        config.auto_execute        = false
        config.auto_terminate      = false
        yield config if block_given?
        return config
      end

      def self.persistence_adapter
        @persistence_adapter ||= begin
                                   db_config = ENV['DB_CONN_STRING'] || 'sqlite:/'
                                   puts "Using database configuration: #{db_config}"
                                   Dynflow::PersistenceAdapters::Sequel.new(db_config)
                                 end
      end

      def self.logger_adapter
        @adapter ||= Dynflow::LoggerAdapters::Simple.new $stderr, 4
      end

      def self.coordinator_adapter
        ->(world, _) { CoordiationAdapterWithLog.new(world) }
      end

      # The worlds created by this method are getting terminated after each test run
      def self.instance(&block)
        @instance ||= self.new(test_world_config(&block))
      end

      def initialize(*args)
        super
        @clock = ManagedClock.new
        @executor = InThreadExecutor.new(self)
      end

      def execute(execution_plan_id, done = Concurrent.future)
        @executor.execute(execution_plan_id, done)
      end

      def terminate(future = Concurrent.future)
        run_before_termination_hooks
        @executor.terminate
        coordinator.delete_world(registered_world)
        future.success true
      rescue => e
        future.fail e
      end

      def event(execution_plan_id, step_id, event, done = Concurrent.future)
        @executor.event(execution_plan_id, step_id, event, done)
      end
    end
  end
end
