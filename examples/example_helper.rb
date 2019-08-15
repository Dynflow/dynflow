# frozen_string_literal: true
$:.unshift(File.expand_path('../../lib', __FILE__))

require 'dynflow'

class ExampleHelper
  CONSOLE_URL='http://localhost:4567'
  DYNFLOW_URL="#{CONSOLE_URL}/dynflow"
  SIDEKIQ_URL="#{CONSOLE_URL}/sidekiq"

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
      config.telemetry_adapter   = telemetry_adapter
      config.queues.add(:slow, :pool_size => 3)
      yield config if block_given?
      Dynflow::World.new(config).tap do |world|
        puts "World #{world.id} started..."
      end
    end

    def persistence_conn_string
      ENV['DB_CONN_STRING'] || 'sqlite:/'
    end

    def telemetry_adapter
      if (host = ENV['TELEMETRY_STATSD_HOST'])
        Dynflow::TelemetryAdapters::StatsD.new host
      else
        Dynflow::TelemetryAdapters::Dummy.new
      end
    end

    def persistence_adapter
      Dynflow::PersistenceAdapters::Sequel.new persistence_conn_string
    end

    def logger_adapter
      Dynflow::LoggerAdapters::Simple.new $stderr, Logger::FATAL
    end

    def run_web_console(world = ExampleHelper.world)
      require 'dynflow/web'
      dynflow_console = Dynflow::Web.setup do
        set :world, world
      end
      apps = { '/dynflow' => dynflow_console }
      puts "Starting Dynflow console at #{DYNFLOW_URL}"
      begin
        require 'sidekiq/web'
        apps['/sidekiq'] = Sidekiq::Web
        puts "Starting Sidekiq console at #{SIDEKIQ_URL}"
      rescue LoadError
        puts 'Sidekiq not around, not mounting the console'
      end

      app = Rack::URLMap.new(apps)
      Rack::Server.new(:app => app, :Host => '0.0.0.0', :Port => URI.parse(CONSOLE_URL).port).start
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
