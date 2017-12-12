require 'rails'
require 'active_record'

module Dynflow
  class Rails
    class Configuration
      # the number of threads in the pool handling the execution
      attr_accessor :pool_size

      # the size of db connection pool
      attr_accessor :db_pool_size

      # set true if the executor runs externally (by default true in procution, othewise false)
      attr_accessor :remote
      alias remote? remote

      # what transaction adapater should be used, by default, it uses the ActiveRecord
      # based adapter, expecting ActiveRecord is used as ORM in the application
      attr_accessor :transaction_adapter

      attr_accessor :eager_load_paths

      attr_accessor :lazy_initialization

      # what rake tasks should run their own executor, not depending on the external one
      attr_accessor :rake_tasks_with_executor

      # if true, the ForemanTasks::Concerns::ActionTriggering will make
      # no effect. Useful for testing, where we mignt not want to execute
      # the orchestration tied to the models.
      attr_accessor :disable_active_record_actions

      def initialize
        self.pool_size                = 5
        self.db_pool_size             = pool_size + 5
        self.remote                   = ::Rails.env.production?
        self.transaction_adapter      = ::Dynflow::TransactionAdapters::ActiveRecord.new
        self.eager_load_paths         = []
        self.lazy_initialization      = !::Rails.env.production?
        self.rake_tasks_with_executor = %w(db:migrate db:seed)

        @on_init = []
      end

      # Action related info such as exceptions raised inside the actions' methods
      # To be overridden in the Rails application
      def action_logger
        ::Rails.logger
      end

      # Dynflow related info about the progress of the execution
      # To be overridden in the Rails application
      def dynflow_logger
        ::Rails.logger
      end

      def on_init(&block)
        @on_init << block
      end

      def run_on_init_hooks(world)
        @on_init.each { |init| init.call(world) }
      end

      def initialize_world(world_class = ::Dynflow::World)
        world_class.new(world_config)
      end

      # No matter what config.remote says, when the process is marked as executor,
      # it can't be remote
      def remote?
        !::Rails.application.dynflow.executor? &&
          !rake_task_with_executor? &&
          @remote
      end

      def rake_task_with_executor?
        return false unless defined?(::Rake) && ::Rake.respond_to?(:application)

        ::Rake.application.top_level_tasks.any? do |rake_task|
          rake_tasks_with_executor.include?(rake_task)
        end
      end

      def increase_db_pool_size?
        !::Rails.env.test?
      end

      # To avoid pottential timeouts on db connection pool, make sure
      # we have the pool bigger than the thread pool
      def increase_db_pool_size
        if increase_db_pool_size?
          ::ActiveRecord::Base.connection_pool.disconnect!

          config = ::ActiveRecord::Base.configurations[::Rails.env]
          config['pool'] = db_pool_size if config['pool'].to_i < db_pool_size
          ::ActiveRecord::Base.establish_connection(config)
        end
      end

      # generates the options hash consumable by the Dynflow's world
      def world_config
        ::Dynflow::Config.new.tap do |config|
          config.auto_rescue         = true
          config.logger_adapter      = ::Dynflow::LoggerAdapters::Delegator.new(action_logger, dynflow_logger)
          config.pool_size           = 5
          config.persistence_adapter = initialize_persistence
          config.transaction_adapter = transaction_adapter
          config.executor            = ->(world, _) { initialize_executor(world) }
          config.connector           = ->(world, _) { initialize_connector(world) }

          # we can't do any operation until the Rails.application.dynflow.world is set
          config.auto_execute        = false
        end
      end

      protected

      def default_sequel_adapter_options
        db_config            = ::ActiveRecord::Base.configurations[::Rails.env].dup
        db_config['adapter'] = db_config['adapter'].gsub(/_?makara_?/, '')
        db_config['adapter'] = 'postgres' if db_config['adapter'] == 'postgresql'
        db_config['max_connections'] = db_pool_size if increase_db_pool_size?

        if db_config['adapter'] == 'sqlite3'
          db_config['adapter'] = 'sqlite'
          database = db_config['database']
          unless database == ':memory:'
            # We need to create separate database for sqlite
            # to avoid lock conflicts on the database
            db_config['database'] = "#{File.dirname(database)}/dynflow-#{File.basename(database)}"
          end
        end
        db_config
      end

      def initialize_executor(world)
        if remote?
          false
        else
          ::Dynflow::Executors::Parallel.new(world, pool_size)
        end
      end

      def initialize_connector(world)
        ::Dynflow::Connectors::Database.new(world)
      end

      # Sequel adapter based on Rails app database.yml configuration
      def initialize_persistence
        ::Dynflow::PersistenceAdapters::Sequel.new(default_sequel_adapter_options)
      end
    end
  end
end
