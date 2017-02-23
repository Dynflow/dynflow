require 'fileutils'

module Dynflow
  class Rails
    class Daemon
      # Load the Rails environment and initialize the executor in this thread.
      def run(rails_root = Dir.pwd)
        STDOUT.puts('Starting Rails environment')
        rails_env_file = File.expand_path('./config/environment.rb', rails_root)
        unless File.exist?(rails_env_file)
          raise "#{rails_root} doesn't seem to be a Rails root directory"
        end
        ::Rails.application.dynflow.executor!
        require rails_env_file
        STDOUT.puts('Everything ready')
        sleep
      ensure
        STDOUT.puts('Exiting')
      end

      # run the executor as a daemon
      def run_background(command = 'start', options = {})
        default_options = { rails_root: Dir.pwd,
                            process_name: 'dynflow_executor',
                            pid_dir: File.join(::Rails.root, 'tmp', 'pids'),
                            log_dir: File.join(::Rails.root, 'log'),
                            wait_attempts: 300,
                            wait_sleep: 1,
                            executors_count: (ENV['EXECUTORS_COUNT'] || 1).to_i }
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
          Daemons.run_proc(options[:process_name],
                           :multiple => true,
                           :dir => options[:pid_dir],
                           :log_dir => options[:log_dir],
                           :dir_mode => :normal,
                           :monitor => true,
                           :log_output => true,
                           :ARGV => [command]) do |*_args|
                             begin
                               ::Logging.reopen
                               run(options[:rails_root])
                             rescue => e
                               STDERR.puts e.message
                               ::Rails.logger.exception('Failed running Dynflow daemon', e)
                               exit 1
                             end
                           end
        end
      end

      protected

      def world
        ::Rails.application.dynflow.world
      end
    end
  end
end
