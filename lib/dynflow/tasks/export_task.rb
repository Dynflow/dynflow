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

        @task_file = nil # Filename of the resulting file
        # Search options
        @task_days    = nil # Number of days
        @task_format  = nil # One of html, csv, json
        @task_ids     = nil # Comma separated list of task ids
        @task_states  = nil # Comma separated list of task states
        @task_results = nil # Comma separated list of task results
        @task_mod     = 100 # Report progress on every task_mod-th task
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
          @task_file = "/tmp/task-export-#{Time.now.to_i}.#{filetype}"
      end

      def task_format
        ENV['TASK_FORMAT'] || @task_format || 'html'
      end

      def task_days
        ENV['TASK_DAYS'] || @task_days
      end

      def task_mod
        @task_mod ||= ENV['task_mod'] || @task_mod
      end

      def task_states
        return @task_states if @task_states
        @task_states = ENV['TASK_STATES'].split(',') if ENV['TASK_STATES']
      end

      def task_results
        return @task_results if @task_results
        @task_results = ENV['TASK_RESULTS'].split(',') if ENV['TASK_RESULTS']
      end

      def task_ids
        return @task_ids if @task_ids
        @task_ids = ENV['TASK_IDS'].split(',') if ENV['TASK_IDS']
      end

      def task_compress
        ENV['TASK_COMPRESS'] || @task_compress || 'yes'
      end

      private

      def compress?
        task_compress.downcase == 'yes'
      end

      def export
        if plans_or_ids.empty?
          puts("Nothing to export, exiting")
          return
        end

        puts "Exporting #{plans_or_ids.count} tasks"
        File.open(task_file, 'w') do |f|
          with_compression(f) do |io|
            manager = case task_format
                      when 'html'
                        ::Dynflow::Exporters::Tar.prepare_html_export io, plans_or_ids, world
                      when 'json'
                        ::Dynflow::Exporters::Tar.new(world, Exporters::JSON.new(:with_full_sub_plans => false), io)
                      when 'csv'
                        ::Dynflow::Exporters::ExportManager.new(world, ::Dynflow::Exporters::CSV.new, io)
                      else
                        raise "Unknown export format '#{task_format}'"
                      end
            manager.add(plans_or_ids).export_collection { |_| progress_report }
          end
        end
        puts "Exported tasks as #{task_file}"
      end

      # Should return an Array containing ExecutionPlans or ids
      def plans_or_ids
        @plans ||= world.persistence.find_execution_plans_attributes([:uuid], :filters => filter).flatten
      end

      def progress_report(_uuid = nil)
        @counter ||= 0
        @counter += 1
        puts "Exported #{@counter}/#{@plans.size} tasks" if @counter % task_mod == 0
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

        # Nothing provided, exporting with some default values
        if filters_provided?
          # Collect all provided filters into the filters array
          filters = []
          # Select tasks with specified ids
          filters << { :uuid => task_ids } if task_ids
          # Select tasks in specified states
          filters << { :state => task_states } if task_states
          # Select tasks with specified results
          filters << { :result => task_results } if task_results

          if (days = task_days) # Limit by age
            filters << { :started_at => last_days(days.to_i) }
          end

          filter = Sequel.&(*filters)
        else
          # Tasks started in last 7 days (in any state)
          last_week = { :started_at => last_days(7) }
          # Tasks started in last 60 days where result != success
          last_two_months = Sequel.&(Sequel.~(:result => 'success'),
                                     { :started_at => last_days(60) })
          # Select tasks matching either of the two
          filter = Sequel.|(last_week, last_two_months)
        end

        filter
      end

      def filters_provided?
        task_ids || task_states || task_days || task_results
      end

      def last_days(count)
        ((Date.today - count)..(Date.today))
      end

      def filetype
        suffix = task_format == 'csv' ? 'csv' : 'tar'
        suffix = suffix + '.gz' if compress?
        suffix
      end

      def with_compression(f, &block)
        if compress?
          begin
            gzip_f = Zlib::GzipWriter.new(f)
            yield gzip_f
          ensure
            gzip_f.close
          end
        else
          yield f
        end
      end
    end
  end
end
