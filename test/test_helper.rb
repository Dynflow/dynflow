require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/spec'

if ENV['RM_INFO']
  require 'minitest/reporters'
  MiniTest::Reporters.use!
end

load_path = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH << load_path unless $LOAD_PATH.include? load_path

require 'dynflow'
require 'dynflow/testing'
require 'pry'

require 'support/code_workflow_example'
require 'support/middleware_example'
require 'support/rescue_example'
require 'support/test_execution_log'

# To be able to stop a process in some step and perform assertions while paused
class TestPause

  def self.setup
    @pause = Concurrent::IVar.new
    @ready = Concurrent::IVar.new
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
      @ready.set(true)
      @pause.wait
    end
  end

  # in the block perform assertions
  def self.when_paused
    if @pause
      @ready.wait # wait till we are paused
      yield
      @pause.set(true) # resume the run
    else
      raise 'the TestPause class was not setup'
    end
  end
end

module WorldInstance
  def self.world
    @world ||= create_world
  end

  def self.remote_world
    return @remote_world if @remote_world
    @listener, @remote_world = create_remote_world world
    @remote_world
  end

  def self.logger_adapter
    @adapter ||= Dynflow::LoggerAdapters::Simple.new $stderr, 4
  end

  def self.create_world(options = {})
    options = { pool_size:           5,
                persistence_adapter: Dynflow::PersistenceAdapters::Sequel.new('sqlite:/'),
                transaction_adapter: Dynflow::TransactionAdapters::None.new,
                logger_adapter:      logger_adapter,
                auto_rescue:         false }.merge(options)
    Dynflow::World.new(options)
  end

  def self.create_remote_world(world)
    @counter    ||= 0
    socket_path = Dir.tmpdir + "/dynflow_remote_#{@counter+=1}"
    listener    = Dynflow::Listeners::Socket.new world, socket_path
    world       = Dynflow::World.new(
        logger_adapter:      logger_adapter,
        auto_terminate:      false,
        persistence_adapter: -> remote_world { world.persistence.adapter },
        transaction_adapter: Dynflow::TransactionAdapters::None.new,
        executor:            -> remote_world do
          Dynflow::Executors::RemoteViaSocket.new(remote_world, socket_path)
        end)
    return listener, world
  end

  def self.terminate
    remote_world.terminate.wait if @remote_world
    world.terminate.wait if @world

    @remote_world = @world = nil
  end

  def world
    WorldInstance.world
  end

  def remote_world
    WorldInstance.remote_world
  end
end

Concurrent.configuration.auto_terminate = false
MiniTest.after_run do
  Concurrent.finalize_global_executors
end

# ensure there are no unresolved Futures at the end or being GCed
future_tests = -> do
  ivar_creations  = {}
  non_ready_ivars = {}

  MiniTest.after_run do
    WorldInstance.terminate
  end

  Concurrent::IVar.singleton_class.send :define_method, :new do |*args, &block|
    super(*args, &block).tap do |ivar|
      ivar_creations[ivar.object_id]  = caller(3)
      non_ready_ivars[ivar.object_id] = true
    end
  end

  original_method = Concurrent::IVar.instance_method :complete
  Concurrent::IVar.send :define_method, :complete do |*args|
    begin
      original_method.bind(self).call *args
    ensure
      non_ready_ivars.delete self.object_id
    end
  end

  MiniTest.after_run do
    non_ready_ivars.delete_if { |id, _| ObjectSpace._id2ref(id).completed? }
    unless non_ready_ivars.empty?
      unified = non_ready_ivars.each_with_object({}) do |(id, _), h|
        backtrace_first    = ivar_creations[id][0]
        h[backtrace_first] ||= []
        h[backtrace_first] << id
      end
      raise("there were #{non_ready_ivars.size} non_ready_futures:\n" +
                unified.map do |backtrace, ids|
                  "--- #{ids.size}: #{ids}\n#{ivar_creations[ids.first].join("\n")}"
                end.join("\n"))
    end
  end

  # time out all futures by default
  default_timeout = 8
  wait_method     = Concurrent::IVar.instance_method(:wait)

  Concurrent::IVar.class_eval do
    define_method :wait do |timeout = nil|
      wait_method.bind(self).call(timeout || default_timeout)
    end
  end

end.call

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
    plan_steps = execution_plan.steps.values.find_all do |step|
      step.is_a? Dynflow::ExecutionPlan::Steps::PlanStep
    end
    plan_steps.all? { |plan_step| plan_step.state.must_equal :success, plan_step.error }
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
