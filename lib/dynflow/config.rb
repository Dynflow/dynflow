module Dynflow
  class Config
    include Algebrick::TypeCheck

    class << self
      def config_attr(name, *types, &default)
        self.send(:define_method, "validate_#{ name }!") do |value|
          Type! value, *types unless types.empty?
        end
        self.send(:define_method, name) do
          var_name = "@#{ name }"
          if instance_variable_defined?(var_name)
            return instance_variable_get(var_name)
          else
            return default
          end
        end
        self.send(:attr_writer, name)
      end
    end

    class ForWorld
      attr_reader :world, :config

      def initialize(config, world)
        @config = config
        @world  = world
        @cache  = {}
      end

      def validate
        @config.validate(self)
      end

      def method_missing(name)
        return @cache[name] if @cache.key?(name)
        value = @config.send(name)
        value = value.call(@world, self) if value.is_a? Proc
        @config.send("validate_#{ name }!", value)
        @cache[name] = value
      end
    end

    config_attr :logger_adapter, LoggerAdapters::Abstract do
      LoggerAdapters::Simple.new
    end

    config_attr :transaction_adapter, TransactionAdapters::Abstract do
      TransactionAdapters::None.new
    end

    config_attr :persistence_adapter, PersistenceAdapters::Abstract do
      PersistenceAdapters::Sequel.new('sqlite:/')
    end

    config_attr :pool_size, Fixnum do
      5
    end

    config_attr :executor, Executors::Abstract, FalseClass do |world, config|
      Executors::Parallel.new(world, config.pool_size)
    end

    config_attr :connector, Connectors::Abstract do |world|
      Connectors::Direct.new(world)
    end

    config_attr :auto_rescue, Algebrick::Types::Boolean do
      false
    end

    config_attr :auto_terminate, Algebrick::Types::Boolean do
      true
    end

    config_attr :auto_execute, Algebrick::Types::Boolean do
      true
    end

    config_attr :consistency_check, Algebrick::Types::Boolean do
      true
    end

    config_attr :action_classes do
      Action.all_children
    end

    def validate(config_for_world)
      if defined? ::ActiveRecord::Base
        ar_pool_size = ::ActiveRecord::Base.connection_pool.instance_variable_get(:@size)
        if (config_for_world.pool_size / 2.0) > ar_pool_size
          config_for_world.world.logger.warn 'Consider increasing ActiveRecord::Base.connection_pool size, ' +
              "it's #{ar_pool_size} but there is #{config_for_world.pool_size} " +
                              'threads in Dynflow pool.'
        end
      end
    end
  end
end
