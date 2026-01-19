# frozen_string_literal: true

require 'rails'
require 'active_record'

module Dynflow
  class Rails
    class Configuration
      # the number of threads in the pool handling the execution
      attr_accessor :pool_size

      # the size of db connection pool, if not set, it's calculated
      # from the amount of workers in the pool
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
        self.remote                   = ::Rails.env.production?
        self.transaction_adapter      = ::Dynflow::TransactionAdapters::ActiveRecord.new
        self.eager_load_paths         = []
        self.lazy_initialization      = !::Rails.env.production?
        self.rake_tasks_with_executor = %w(db:migrate db:seed)

        @on_init            = []
        @on_executor_init   = []
        @post_executor_init = []
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

      def on_init(executor = true, &block)
        destination = executor ? @on_executor_init : @on_init
        destination << block
      end

      def run_on_init_hooks(executor, world)
        source = executor ? @on_executor_init : @on_init
        source.each { |init| init.call(world) }
      end

      def post_executor_init(&block)
        @post_executor_init << block
      end

      def run_post_executor_init_hooks(world)
        @post_executor_init.each { |init| init.call(world) }
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
        !::Rails.env.test? && (!remote? || sidekiq_worker?)
      end

      def sidekiq_worker?
        defined?(::Sidekiq) && ::Sidekiq.configure_server { |c| c[:queues].any? }
      end

      def calculate_db_pool_size(world)
        return self.db_pool_size if self.db_pool_size

        base_value = 5
        if defined?(::Sidekiq)
          Sidekiq.configure_server { |c| c[:concurrency] } + base_value
        else
          world.config.queues.values.inject(base_value) do |pool_size, pool_options|
            pool_size += pool_options[:pool_size]
          end
        end
      end

      # To avoid pottential timeouts on db connection pool, make sure
      # we have the pool bigger than the thread pool
      def increase_db_pool_size(world = nil)
        if world.nil?
          warn 'Deprecated: using `increase_db_pool_size` outside of Dynflow code is not needed anymore'
          return
        end
        if increase_db_pool_size?
          db_pool_size = calculate_db_pool_size(world)

          base_config = ::ActiveRecord::Base.configurations.configs_for(env_name: ::Rails.env)[0]
          config = if base_config.respond_to?(:configuration_hash)
                     ::Dynflow::Utils::IndifferentHash.new(base_config.configuration_hash.dup)
                   else
                     base_config.config.dup
                   end

          return unless config['pool'].to_i < db_pool_size

          config['pool'] = db_pool_size
          ::ActiveRecord::Base.connection_pool.disconnect!
          ::ActiveRecord::Base.establish_connection(config)
        end
      end

      # generates the options hash consumable by the Dynflow's world
      def world_config
        @world_config ||= ::Dynflow::Config.new.tap do |config|
          config.auto_rescue         = true
          config.logger_adapter      = ::Dynflow::LoggerAdapters::Delegator.new(action_logger, dynflow_logger)
          config.pool_size           = self.pool_size
          config.persistence_adapter = ->(world, _) { initialize_persistence(world) }
          config.transaction_adapter = transaction_adapter
          config.executor            = ->(world, _) { initialize_executor(world) }
          config.connector           = ->(world, _) { initialize_connector(world) }

          # we can't do any operation until the Rails.application.dynflow.world is set
          config.auto_execute        = false
          config.auto_validity_check = false
          if sidekiq_worker? && !Sidekiq.configure_server { |c| c[:queues].include?("dynflow_orchestrator") }
            config.delayed_executor = nil
          end
        end
      end

      # expose the queues definition to Rails developers
      def queues
        world_config.queues
      end

      protected

      def default_sequel_adapter_options(world)
        base_config = ::ActiveRecord::Base.configurations.configs_for(env_name: ::Rails.env)[0]
        db_config = if base_config.respond_to?(:configuration_hash)
                      ::Dynflow::Utils::IndifferentHash.new(base_config.configuration_hash.dup)
                    else
                      base_config.config.dup
                    end
        db_config['adapter'] = db_config['adapter'].gsub(/_?makara_?/, '')
        db_config['adapter'] = 'postgres' if db_config['adapter'] == 'postgresql'
        db_config['max_connections'] = calculate_db_pool_size(world) if increase_db_pool_size?

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
          if defined?(::Sidekiq) && Sidekiq.configure_server { |c| c[:dynflow_executor] }
            ::Dynflow::Executors::Sidekiq::Core
          else
            ::Dynflow::Executors::Parallel::Core
          end
        end
      end

      def initialize_connector(world)
        ::Dynflow::Connectors::Database.new(world)
      end

      def persistence_class
        ::Dynflow::PersistenceAdapters::Sequel
      end

      # Sequel adapter based on Rails app database.yml configuration
      def initialize_persistence(world, options = {})
        persistence_class.new(default_sequel_adapter_options(world).merge(options))
      end
    end
  end
end
