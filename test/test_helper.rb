require 'bundler/setup'
require 'minitest/reporters'
require 'minitest/autorun'
require 'minitest/spec'

MiniTest::Reporters.use! if ENV['RM_INFO']

load_path = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH << load_path unless $LOAD_PATH.include? load_path

require 'dynflow'
require 'dynflow/testing'
begin require 'pry'; rescue LoadError; nil end

require 'support/code_workflow_example'
require 'support/middleware_example'
require 'support/rescue_example'
require 'support/dummy_example'
require 'support/test_execution_log'

Concurrent.disable_at_exit_handlers!

# To be able to stop a process in some step and perform assertions while paused
class TestPause

  def self.setup
    @pause = Concurrent.future
    @ready = Concurrent.future
  end

  def self.teardown
    @pause = nil
    @ready = nil
  end

  # to be called from action
  def self.pause
    if !@pause
      raise 'the TestPause class was not setup'
    elsif @ready.completed?
      raise 'you can pause only once'
    else
      @ready.success(true)
      @pause.wait
    end
  end

  # in the block perform assertions
  def self.when_paused
    if @pause
      @ready.wait # wait till we are paused
      yield
      @pause.success(true) # resume the run
    else
      raise 'the TestPause class was not setup'
    end
  end
end

class CoordiationAdapterWithLog < Dynflow::CoordinatorAdapters::Sequel
  attr_reader :lock_log
  def initialize(*args)
    @lock_log = []
    super
  end

  def create_record(record)
    @lock_log << "lock #{record.id}" if record.is_a? Dynflow::Coordinator::Lock
    super
  end

  def delete_record(record)
    @lock_log << "unlock #{record.id}" if record.is_a? Dynflow::Coordinator::Lock
    super
  end
end

module WorldFactory

  def self.created_worlds
    @created_worlds ||= []
  end

  def self.test_world_config
    config                     = Dynflow::Config.new
    config.persistence_adapter = persistence_adapter
    config.logger_adapter      = logger_adapter
    config.coordinator_adapter = coordinator_adapter
    config.delayed_executor    = nil
    config.auto_rescue         = false
    config.auto_validity_check = false
    config.exit_on_terminate   = false
    config.auto_execute        = false
    config.auto_terminate      = false
    yield config if block_given?
    return config
  end

  # The worlds created by this method are getting terminated after each test run
  def self.create_world(klass = Dynflow::World, &block)
    klass.new(test_world_config(&block)).tap do |world|
      created_worlds << world
    end
  end

  # This world survives though the whole run of the test suite: careful with it, it can
  # introduce unnecessary test dependencies
  def self.logger_adapter
    @adapter ||= Dynflow::LoggerAdapters::Simple.new $stderr, 4
  end

  def self.persistence_adapter
    @persistence_adapter ||= begin
                               db_config = ENV['DB_CONN_STRING'] || 'sqlite:/'
                               puts "Using database configuration: #{db_config}"
                               Dynflow::PersistenceAdapters::Sequel.new(db_config)
                             end
  end

  def self.coordinator_adapter
    ->(world, _) { CoordiationAdapterWithLog.new(world) }
  end

  def self.clean_coordinator_records
    persistence_adapter = WorldFactory.persistence_adapter
    persistence_adapter.find_coordinator_records({}).each do |w|
      warn "Unexpected coordinator record: #{ w }"
      persistence_adapter.delete_coordinator_record(w[:class], w[:id])
    end
  end

  def self.terminate_worlds
    created_worlds.map(&:terminate).map(&:wait)
    created_worlds.clear
  end
end

module TestHelpers
  # allows to create the world inside the tests, using the `connector`
  # and `persistence adapter` from the test context: usefull to create
  # multi-world topology for a signle test
  def create_world(with_executor = true, &block)
    WorldFactory.create_world do |config|
      config.connector = connector
      config.persistence_adapter = persistence_adapter
      unless with_executor
        config.executor = false
      end
      block.call(config) if block
    end
  end

  def connector_polling_interval(world)
    if world.persistence.adapter.db.class.name == "Sequel::Postgres::Database"
      5
    else
      0.005
    end
  end

  # waits for the passed block to return non-nil value and reiterates it while getting false
  # (till some reasonable timeout). Useful for forcing the tests for some event to occur
  def wait_for
    30.times do
      ret = yield
      return ret if ret
      sleep 0.3
    end
    raise 'waiting for something to happen was not successful'
  end

  def executor_id_for_plan(execution_plan_id)
    if lock = client_world.coordinator.find_locks(class: Dynflow::Coordinator::ExecutionLock.name,
                                                  id: "execution-plan:#{execution_plan_id}").first
      lock.world_id
    end
  end

  def trigger_waiting_action
    triggered = client_world.trigger(Support::DummyExample::EventedAction)
    wait_for { executor_id_for_plan(triggered.id) } # waiting for the plan to be picked by an executor
    triggered
  end

  # trigger an action, and keep it running while yielding the block
  def while_executing_plan
    triggered = trigger_waiting_action

    executor_id = wait_for do
      executor_id_for_plan(triggered.id)
    end

    wait_for do
      client_world.persistence.load_execution_plan(triggered.id).state == :running
    end

    executor = WorldFactory.created_worlds.find { |e| e.id == executor_id }
    raise "Could not find an executor with id #{executor_id}" unless executor
    yield executor
    return triggered
  end

  # finish the plan triggered by the `while_executing_plan` method
  def finish_the_plan(triggered)
    wait_for do
      client_world.persistence.load_execution_plan(triggered.id).state == :running &&
        client_world.persistence.load_step(triggered.id, 2, client_world).state == :suspended
    end
    client_world.event(triggered.id, 2, 'finish')
    return triggered.finished.value
  end

  def assert_plan_reexecuted(plan)
    assert_equal :stopped, plan.state
    assert_equal :success, plan.result
    assert_equal plan.execution_history.map(&:name),
                 ['start execution',
                  'terminate execution',
                  'start execution',
                  'finish execution']
    refute_equal plan.execution_history.first.world_id, plan.execution_history.to_a.last.world_id
  end
end

class MiniTest::Test
  def setup
    WorldFactory.clean_coordinator_records
  end

  def teardown
    WorldFactory.terminate_worlds
  end
end

# ensure there are no unresolved events at the end or being GCed
events_test = -> do
  event_creations  = {}
  non_ready_events = {}

  Concurrent::Edge::Event.singleton_class.send :define_method, :new do |*args, &block|
    super(*args, &block).tap do |event|
      event_creations[event.object_id] = caller(4)
    end
  end

  [Concurrent::Edge::Event, Concurrent::Edge::Future].each do |future_class|
    original_complete_method = future_class.instance_method :complete_with
    future_class.send :define_method, :complete_with do |*args|
      begin
        original_complete_method.bind(self).call(*args)
      ensure
        event_creations.delete(self.object_id)
      end
    end
  end

  MiniTest.after_run do
    Concurrent::Actor.root.ask!(:terminate!)

    non_ready_events = ObjectSpace.each_object(Concurrent::Edge::Event).map do |event|
      event.wait(1)
      unless event.completed?
        event.object_id
      end
    end.compact

    # make sure to include the ids that were garbage-collected already
    non_ready_events = (non_ready_events + event_creations.keys).uniq

    unless non_ready_events.empty?
      unified = non_ready_events.each_with_object({}) do |(id, _), h|
        backtrace_key = event_creations[id].hash
        h[backtrace_key] ||= []
        h[backtrace_key] << id
      end
      raise("there were #{non_ready_events.size} non_ready_events:\n" +
            unified.map do |_, ids|
                  "--- #{ids.size}: #{ids}\n#{event_creations[ids.first].join("\n")}"
                end.join("\n"))
    end
  end

  # time out all futures by default
  default_timeout = 8
  wait_method     = Concurrent::Edge::Event.instance_method(:wait)

  Concurrent::Edge::Event.class_eval do
    define_method :wait do |timeout = nil|
      wait_method.bind(self).call(timeout || default_timeout)
    end
  end

end

events_test.call

class ConcurrentRunTester
  def initialize
    @enter_future, @exit_future = Concurrent.future, Concurrent.future
  end

  def while_executing(&block)
    @thread = Thread.new do
      block.call(self)
    end
    @enter_future.wait(1)
  end

  def pause
    @enter_future.success(true)
    @exit_future.wait(1)
  end

  def finish
    @exit_future.success(true)
    @thread.join
  end
end

module PlanAssertions

  def inspect_flow(execution_plan, flow)
    out = ""
    inspect_subflow(out, execution_plan, flow, "")
    out
  end

  def inspect_plan_steps(execution_plan)
    out = ""
    inspect_plan_step(out, execution_plan, execution_plan.root_plan_step, "")
    out
  end

  def assert_planning_success(execution_plan)
    execution_plan.plan_steps.all? { |plan_step| plan_step.state.must_equal :success, plan_step.error }
  end

  def assert_run_flow(expected, execution_plan)
    assert_planning_success(execution_plan)
    inspect_flow(execution_plan, execution_plan.run_flow).chomp.must_equal dedent(expected).chomp
  end

  def assert_finalize_flow(expected, execution_plan)
    assert_planning_success(execution_plan)
    inspect_flow(execution_plan, execution_plan.finalize_flow).chomp.must_equal dedent(expected).chomp
  end

  def assert_run_flow_equal(expected_plan, execution_plan)
    expected = inspect_flow(expected_plan, expected_plan.run_flow)
    current  = inspect_flow(execution_plan, execution_plan.run_flow)
    assert_equal expected, current
  end

  def assert_steps_equal(expected, current)
    current.id.must_equal expected.id
    current.class.must_equal expected.class
    current.state.must_equal expected.state
    current.action_class.must_equal expected.action_class
    current.action_id.must_equal expected.action_id

    if expected.respond_to?(:children)
      current.children.must_equal(expected.children)
    end
  end

  def assert_plan_steps(expected, execution_plan)
    inspect_plan_steps(execution_plan).chomp.must_equal dedent(expected).chomp
  end

  def assert_finalized(action_class, input)
    assert_executed(:finalize, action_class, input)
  end

  def assert_executed(phase, action_class, input)
    log = TestExecutionLog.send(phase).log

    found_log = log.any? do |(logged_action_class, logged_input)|
      action_class == logged_action_class && input == logged_input
    end

    unless found_log
      message = ["#{action_class} with input #{input.inspect} not executed in #{phase} phase"]
      message << "following actions were executed:"
      log.each do |(logged_action_class, logged_input)|
        message << "#{logged_action_class} #{logged_input.inspect}"
      end
      raise message.join("\n")
    end
  end

  def inspect_subflow(out, execution_plan, flow, prefix)
    case flow
    when Dynflow::Flows::Atom
      out << prefix
      out << flow.step_id.to_s << ': '
      step = execution_plan.steps[flow.step_id]
      out << step.action_class.to_s[/\w+\Z/]
      out << "(#{step.state})"
      out << ' '
      action = execution_plan.world.persistence.load_action(step)
      out << action.input.inspect
      unless step.state == :pending
        out << ' --> '
        out << action.output.inspect
      end
      out << "\n"
    else
      out << prefix << flow.class.name << "\n"
      flow.sub_flows.each do |sub_flow|
        inspect_subflow(out, execution_plan, sub_flow, prefix + '  ')
      end
    end
    out
  end

  def inspect_plan_step(out, execution_plan, plan_step, prefix)
    out << prefix
    out << plan_step.action_class.to_s[/\w+\Z/]
    out << "\n"
    plan_step.children.each do |sub_step_id|
      sub_step = execution_plan.steps[sub_step_id]
      inspect_plan_step(out, execution_plan, sub_step, prefix + '  ')
    end
    out
  end

  def dedent(string)
    dedent = string.scan(/^ */).map { |spaces| spaces.size }.min
    string.lines.map { |line| line[dedent..-1] }.join
  end
end
