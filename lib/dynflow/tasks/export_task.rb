require 'rake'
require 'rake/tasklib'

module Dynflow
  module Tasks
    class Export < ::Rake::TaskLib

      attr_accessor :name, :world
      attr_writer :task_days
      attr_writer :task_file
      attr_writer :task_format
      attr_writer :task_search
      attr_writer :plans

      def initialize(name = :export_tasks)
        @name = name
        @world = nil
        @plans = nil

        @task_file   = nil
        # Search options
        @task_days   = nil
        @task_format = nil
        @task_search = nil
        yield self if block_given?
        define
      end

      def define
        desc 'Export tasks'
        task @name do
          export
        end
        self
      end

      def task_file
        ENV['TASK_FILE'] ||
          @task_file ||
          "/tmp/task-export-#{Time.now.to_i}.#{task_format == 'csv' ? 'csv' : 'tar.gz'}"
      end

      def task_format
        ENV['TASK_FORMAT'] || @task_format || 'html'
      end

      def task_search
        ENV['TASK_SEARCH'] || @task_search
      end

      def task_days
        ENV['TASK_DAYS'] || @task_days
      end

      private

      def export
        if plans.empty?
          puts("Nothing to export, exiting")
          return
        end

        puts "Exporting #{plans.count} tasks"
        content = case task_format
                  when 'html'
                    require 'pry'; binding.pry
                    ::Dynflow::Exporters::Tar.full_html_export plans
                  when 'json'
                    ::Dynflow::Exporters::Tar.full_json_export plans
                  when 'csv'
                    ::Dynflow::Exporters::CSV.new
                      .add_many(plans).result
                  else
                    raise "Unknown export format '#{format}'"
                  end
        File.write(task_file, content)
        puts "Exported tasks as #{task_file}"
      end

      def plans
        @plans ||= world.persistence.find_execution_plans(:filters => filter)
      end

      def filter
        klass = world.persistence.adapter.class
        if klass == ::Dynflow::PersistenceAdapters::Sequel
          sequel_filter
        else
          raise "Unsupporter database adapter #{klass}."
        end
      end

      def sequel_filter
        filter = nil

        if task_search.nil? && task_days.nil?
          # Tasks started in last 7 days (in any state)
          last_week = { :started_at => last_days(7) }
          # Tasks started in last 60 days where state != success
          last_two_months = Sequel.&(Sequel.~(:result => 'success'),
                                     { :started_at => last_days(60) })
          # Select tasks matching either of the two
          filter = Sequel.|(last_week, last_two_months)
        elsif task_search
          # Use the search filter provided
          filter = Sequel.&(task_search)
        end

        if (days = task_days)
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
