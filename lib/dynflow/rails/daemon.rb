# frozen_string_literal: true
require 'fileutils'
require 'get_process_mem'
require 'active_support/core_ext/numeric/bytes'

module Dynflow
  class Rails
    class Daemon
      attr_reader :dynflow_memory_watcher_class, :daemons_class

      # make Daemon dependency injection ready for testing purposes
      def initialize(
        dynflow_memory_watcher_class = ::Dynflow::Watchers::MemoryConsumptionWatcher,
        non_default_daemons_class = nil
      )
        @dynflow_memory_watcher_class = dynflow_memory_watcher_class
        @daemons_class = non_default_daemons_class
      end

      def daemons_class
        @daemons_class || ::Daemons
      end

      # Load the Rails environment and initialize the executor in this thread.
      def run(rails_root = Dir.pwd, options = {})
        STDOUT.puts('Starting Rails environment')
        rails_env_file = File.expand_path('./config/environment.rb', rails_root)
        unless File.exist?(rails_env_file)
          raise "#{rails_root} doesn't seem to be a Rails root directory"
        end

        STDERR.puts("Starting dynflow with the following options: #{options}")

        ::Rails.application.dynflow.executor!

        if options[:memory_limit] && options[:memory_limit].to_i > 0
          ::Rails.application.dynflow.config.on_init do |world|
            memory_watcher = initialize_memory_watcher(world, options[:memory_limit], options)
            world.terminated.on_resolution do
              STDOUT.puts("World has been terminated")
              memory_watcher = nil # the object can be disposed
            end
          end
        end

        require rails_env_file
        ::Rails.application.dynflow.initialize!
        world_id = ::Rails.application.dynflow.world.id
        STDOUT.puts("Everything ready for world: #{world_id}")
        sleep
      ensure
        STDOUT.puts('Exiting')
      end

      # run the executor as a daemon
      def run_background(command = 'start', options = {})
        options = default_options.merge(options)
        FileUtils.mkdir_p(options[:pid_dir])
        begin
          require 'daemons'
        rescue LoadError
          raise "You need to add gem 'daemons' to your Gemfile if you wish to use it."
        end

        unless %w(start stop restart run).include?(command)
          raise "Command exptected to be 'start', 'stop', 'restart', 'run', was #{command.inspect}"
        end

        STDOUT.puts("Dynflow Executor: #{command} in progress")

        options[:executors_count].times do
          daemons_class.run_proc(
            options[:process_name],
            daemons_options(command, options)
          ) do |*_args|
            begin
              ::Logging.reopen
              run(options[:rails_root], options)
            rescue => e
              STDERR.puts e.message
              ::Rails.logger.fatal('Failed running Dynflow daemon')
              ::Rails.logger.fatal(e)
              exit 1
            end
          end
        end
      end

      protected

      def world
        ::Rails.application.dynflow.world
      end

      private

      def daemons_options(command, options)
        {
          :multiple => true,
          :dir => options[:pid_dir],
          :log_dir => options[:log_dir],
          :dir_mode => :normal,
          :monitor => true,
          :log_output => true,
          :log_output_syslog => true,
          :monitor_interval => [options[:memory_polling_interval] / 2, 30].min,
          :force_kill_waittime => options[:force_kill_waittime].try(:to_i),
          :ARGV => [command]
        }
      end

      def default_options
        {
          rails_root: Dir.pwd,
          process_name: 'dynflow_executor',
          pid_dir: "#{::Rails.root}/tmp/pids",
          log_dir: File.join(::Rails.root, 'log'),
          wait_attempts: 300,
          wait_sleep: 1,
          executors_count: (ENV['EXECUTORS_COUNT'] || 1).to_i,
          memory_limit: begin
                          to_gb((ENV['EXECUTOR_MEMORY_LIMIT'] || '')).gigabytes
                        rescue RuntimeError
                          ENV['EXECUTOR_MEMORY_LIMIT'].to_i
                        end,
          memory_init_delay: (ENV['EXECUTOR_MEMORY_MONITOR_DELAY'] || 7200).to_i, # 2 hours
          memory_polling_interval: (ENV['EXECUTOR_MEMORY_MONITOR_INTERVAL'] || 60).to_i,
          force_kill_waittime: (ENV['EXECUTOR_FORCE_KILL_WAITTIME'] || 60).to_i
        }
      end

      def initialize_memory_watcher(world, memory_limit, options)
        watcher_options = {}
        watcher_options[:polling_interval] = options[:memory_polling_interval]
        watcher_options[:initial_wait] = options[:memory_init_delay]
        watcher_options[:memory_checked_callback] = ->(current_memory, memory_limit) do
          log_memory_within_limit(current_memory, memory_limit)
        end
        watcher_options[:memory_limit_exceeded_callback] = ->(current_memory, memory_limit) do
          log_memory_limit_exceeded(current_memory, memory_limit)
        end
        dynflow_memory_watcher_class.new(world, memory_limit, watcher_options)
      end

      def log_memory_limit_exceeded(current_memory, memory_limit)
        message = "Memory level exceeded, registered #{current_memory} bytes, which is greater than #{memory_limit} limit."
        world.logger.error(message)
      end

      def log_memory_within_limit(current_memory, memory_limit)
        message = "Memory level OK, registered #{current_memory} bytes, which is less than #{memory_limit} limit."
        world.logger.debug(message)
      end

      private

      # Taken straight from https://github.com/theforeman/foreman/blob/develop/lib/core_extensions.rb#L142
      # in order to make this class work with any Rails project
      def to_gb(string)
        match_data = string.match(/^(\d+(\.\d+)?) ?(([KMGT]i?B?|B|Bytes))?$/i)
        if match_data.present?
          value, _, unit = match_data[1..3]
        else
          raise "Unknown string: #{string.inspect}!"
        end
        unit ||= :byte # default to bytes if no unit given

        case unit.downcase.to_sym
        when :b, :byte, :bytes then (value.to_f / 1.gigabyte)
        when :tb, :tib, :t, :terabyte then (value.to_f * 1.kilobyte)
        when :gb, :gib, :g, :gigabyte then value.to_f
        when :mb, :mib, :m, :megabyte then (value.to_f / 1.kilobyte)
        when :kb, :kib, :k, :kilobyte then (value.to_f / 1.megabyte)
        else raise "Unknown unit: #{unit.inspect}!"
        end
      end

    end
  end
end
