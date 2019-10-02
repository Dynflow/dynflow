# frozen_string_literal: true
require 'test_helper'
require 'active_support'
require 'mocha/minitest'
require 'logging'
require 'dynflow/testing'
require_relative '../lib/dynflow/rails'

class DaemonTest < ActiveSupport::TestCase
  setup do
    @dynflow_memory_watcher = mock('memory_watcher')
    @daemons = mock('daemons')
    @daemon = ::Dynflow::Rails::Daemon.new(
      @dynflow_memory_watcher,
      @daemons
    )
    @world_class = mock('dummy world factory')
    @dummy_world = ::Dynflow::Testing::DummyWorld.new
    @dummy_world.stubs(:id => '123')
    @dummy_world.stubs(:auto_execute)
    @dummy_world.stubs(:perform_validity_checks => 0)
    @event = Concurrent::Promises.resolvable_event
    @dummy_world.stubs(:terminated).returns(@event)
    @world_class.stubs(:new).returns(@dummy_world)
    @dynflow = ::Dynflow::Rails.new(
      @world_class,
      ::Dynflow::Rails::Configuration.new
    )
    ::Rails.stubs(:application).returns(OpenStruct.new(:dynflow => @dynflow))
    ::Rails.stubs(:root).returns('support/rails')
    ::Rails.stubs(:logger).returns(Logging.logger(STDOUT))
    @dynflow.require!
    @dynflow.config.stubs(:increase_db_pool_size? => false)
    @daemon.stubs(:sleep).returns(true) # don't pause the execution
    @current_folder = File.expand_path('../support/rails/', __FILE__)
    ::ActiveRecord::Base.configurations = { 'development' => {} }
    ::Dynflow::Rails::Configuration.any_instance.stubs(:initialize_persistence).
      returns(WorldFactory.persistence_adapter)
  end

  teardown do
    @event.resolve
    @event.wait
  end

  test 'run command works without memory_limit option specified' do
    @daemon.run(@current_folder)
    @dynflow.initialize!
  end

  test 'runs post_initialization when there are invalid worlds detected' do
    @dummy_world.stubs(:perform_validity_checks => 1)
    @dummy_world.expects(:post_initialization)
    @daemon.run(@current_folder)
    @dynflow.initialize!
  end

  test 'run command creates a watcher if memory_limit option specified' do
    @dynflow_memory_watcher.expects(:new).with do |_world, memory_limit, _watcher_options|
      memory_limit == 1000
    end

    @daemon.run(@current_folder, memory_limit: 1000)
    # initialization should be performed inside the foreman environment,
    # which is mocked here
    @dynflow.initialize!
  end

  test 'run command sets parameters to watcher' do
    @dynflow_memory_watcher.expects(:new).with do |_world, memory_limit, watcher_options|
      memory_limit == 1000 &&
        watcher_options[:polling_interval] == 100 &&
        watcher_options[:initial_wait] == 200
    end

    @daemon.run(
      @current_folder,
      memory_limit: 1000,
      memory_polling_interval: 100,
      memory_init_delay: 200
    )
    @dynflow.initialize!
  end

  test 'run_background command executes run with all params set as a daemon' do
    @daemon.expects(:run).twice.with do |_folder, options|
      options[:memory_limit] == 1000 &&
        options[:memory_init_delay] == 100 &&
        options[:memory_polling_interval] == 200 &&
        options[:force_kill_waittime] == 40
    end
    @daemons.expects(:run_proc).twice.yields

    @daemon.run_background(
      'start',
      executors_count: 2,
      memory_limit: 1000,
      memory_init_delay: 100,
      memory_polling_interval: 200,
      force_kill_waittime: 40
    )
  end

  test 'default options read values from ENV' do
    ENV['EXECUTORS_COUNT'] = '2'
    ENV['EXECUTOR_MEMORY_LIMIT'] = '1gb'
    ENV['EXECUTOR_MEMORY_MONITOR_DELAY'] = '3'
    ENV['EXECUTOR_MEMORY_MONITOR_INTERVAL'] = '4'
    ENV['EXECUTOR_FORCE_KILL_WAITTIME'] = '40'

    actual = @daemon.send(:default_options)

    assert_equal 2, actual[:executors_count]
    assert_equal 1.gigabytes, actual[:memory_limit]
    assert_equal 3, actual[:memory_init_delay]
    assert_equal 4, actual[:memory_polling_interval]
    assert_equal 40, actual[:force_kill_waittime]
  end
end
