module Dynflow
  module Utilities
    class Export

      attr_accessor :task_search, :task_days, :task_format, :task_file, :connection_string

      def initialize
        @connection_string = ENV['DB_CONN_STRING']
        @task_search       = ENV['TASK_SEARCH']
        @task_days         = ENV['TASK_DAYS']
        @task_format       = ENV['TASK_FORMAT']
        @task_file         = ENV['TASK_FILE']
      end

      def export_filename
        @task_file || "/tmp/task-export-#{Time.now.to_i}.#{export_format == 'csv' ? 'csv' : 'tar.gz'}"
      end

      def export_format
        @task_format || 'html'
      end

      def export
        content = case export_format
                  when 'html'
                    ::Dynflow::Exporters::Tar.full_html_export plans
                  when 'json'
                    ::Dynflow::Exporters::Tar.full_json_export plans
                  when 'csv'
                    ::Dynflow::Exporters::CSV.new
                      .add_many(plans).result
                  else
                    raise "Unknown export format '#{format}'"
                  end
        File.write(export_filename, content)
      end

      def plans
        world.persistence.find_execution_plans(:filters => filter)
      end

      def world
        return @world if @world
        config = ::Dynflow::Config.new.tap do |config|
          config.logger_adapter      = ::Dynflow::LoggerAdapters::Simple.new $stdout, 2
          config.pool_size           = 5
          config.persistence_adapter = ::Dynflow::PersistenceAdapters::Sequel.new connection_string
          config.executor            = false
          config.connector           = Proc.new { |world| Dynflow::Connectors::Database.new(world) }
          config.auto_execute        = false
        end
        @world = ::Dynflow::World.new(config)
      end

      def filter
        case world.persistence.adapter
        when ::Dynflow::PersistenceAdapters::Sequel
          sequel_filter
        else
          raise "Unsupporter database adapter #{world.persistence.adapter.class}."
        end
      end

      private

      def sequel_filter
        filter = nil

        if @task_search.nil? && @task_days.nil?
          last_week = { :started_at => last_days(7) }
          last_two_months = Sequel.&(Sequel.~(:result => 'success'),
                                     { :started_at => last_days(60) })
          filter = Sequel.|(last_week, last_two_months)
        elsif @task_search
          filter = Sequel.&(@task_search)
        end

        if (days = @task_days)
          filter = Sequel.&(filter, { :started_at => last_days(days.to_i) })
        end
        filter
      end

      def last_days(count)
        ((Date.today - count)..(Date.today))
      end

    end
  end
end
