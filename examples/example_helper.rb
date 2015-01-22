$:.unshift(File.expand_path('../../lib', __FILE__))

require 'dynflow'

class ExampleHelper
  class << self
    def world
      @world ||= create_world
    end

    def create_world(options = {})
      options = default_world_options.merge(options)
      Dynflow::SimpleWorld.new(options)
    end

    def persistence_conn_string
      ENV['DB_CONN_STRING'] || 'sqlite:/'
    end

    def persistence_adapter
      Dynflow::PersistenceAdapters::Sequel.new persistence_conn_string
    end

    def default_world_options
      { logger_adapter: logger_adapter,
        persistence_adapter: persistence_adapter }
    end

    def logger_adapter
      Dynflow::LoggerAdapters::Simple.new $stderr, 4
    end


    def run_web_console(world = ExampleHelper.world)
      require 'dynflow/web_console'
      dynflow_console = Dynflow::WebConsole.setup do
        set :world, world
      end
      dynflow_console.run!
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
  end
end
