$:.unshift(File.expand_path('../../lib', __FILE__))

require 'dynflow'

class ExampleHelper
  class << self
    def world
      @world ||= create_world
    end

    def set_world(world)
      @world = world
    end

    def create_world
      config = Dynflow::Config.new
      config.persistence_adapter = persistence_adapter
      config.logger_adapter      = logger_adapter
      config.auto_rescue         = false
      yield config if block_given?
      Dynflow::World.new(config).tap do |world|
        puts "World #{world.id} started..."
      end
    end

    def persistence_conn_string
      ENV['DB_CONN_STRING'] || 'sqlite:/'
    end

    def persistence_adapter
      Dynflow::PersistenceAdapters::Sequel.new persistence_conn_string
    end

    def logger_adapter
      Dynflow::LoggerAdapters::Simple.new $stderr, 4
    end

    def run_web_console(world = ExampleHelper.world)
      require 'dynflow/web'
      dynflow_console = Dynflow::Web.setup do
        set :world, world
      end
      Rack::Server.new(:app => dynflow_console, :Port => 4567).start
    end

    # for simulation of the execution failing for the first time
    def something_should_fail!
      @should_fail = true
    end

    # for simulation of the execution failing for the first time
    def something_should_fail?
      @should_fail
    end

    def nothing_should_fail!
      @should_fail = false
    end

    def terminate
      @world.terminate.wait if @world
    end
  end
end

at_exit { ExampleHelper.terminate }
