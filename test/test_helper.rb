require 'test/unit'
require 'minitest/spec'
if ENV['RM_INFO']
  require 'minitest/reporters'
  MiniTest::Reporters.use!
end
require 'dynflow'
require 'pry'

MiniTest::Unit.after_tests { Dynflow::CodeWorkflowExample::PollingService.terminate! }

class TestExecutionLog

  include Enumerable

  def initialize
    @log = []
  end

  def <<(action)
    @log << [action.action_class, action.input]
  end

  def log
    @log
  end

  def each(&block)
    @log.each(&block)
  end

  def size
    @log.size
  end

  def self.setup
    @run, @finalize = self.new, self.new
  end

  def self.teardown
    @run, @finalize = nil, nil
  end

  def self.run
    @run || []
  end

  def self.finalize
    @finalize || []
  end

end

# To be able to stop a process in some step and perform assertions while paused
class TestPause

  def self.setup
    @pause = Dynflow::Future.new
    @ready = Dynflow::Future.new
  end

  def self.teardown
    @pause = nil
    @ready = nil
  end

  # to be called from action
  def self.pause
    if !@pause
      raise 'the TestPause class was not setup'
    elsif @ready.ready?
      raise 'you can pause only once'
    else
      @ready.resolve(true)
      @pause.wait
    end
  end

  # in the block perform assertions
  def self.when_paused
    if @pause
      @ready.wait # wait till we are paused
      yield
      @pause.resolve(true) # resume the run
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
    action_logger  = Logger.new($stderr).tap { |logger| logger.level = Logger::FATAL }
    dynflow_logger = Logger.new($stderr).tap { |logger| logger.level = Logger::WARN }
    Dynflow::LoggerAdapters::Delegator.new(action_logger, dynflow_logger)
  end

  def self.create_world
    Dynflow::SimpleWorld.new logger_adapter: logger_adapter,
                             auto_terminate: false
  end

  def self.create_remote_world(world)
    @counter    ||= 0
    socket_path = Dir.tmpdir + "/dynflow_remote_#{@counter+=1}"
    listener    = Dynflow::Listeners::Socket.new world, socket_path
    world       = Dynflow::SimpleWorld.new(logger_adapter: logger_adapter) do |remote_world|
      { persistence_adapter: world.persistence.adapter,
        executor:            Dynflow::Executors::RemoteViaSocket.new(remote_world, socket_path),
        auto_terminate:      false }
    end
    return listener, world
  end

  def world
    WorldInstance.world
  end

  def remote_world
    WorldInstance.remote_world
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
    plan_steps = execution_plan.steps.values.find_all do |step|
      step.is_a? Dynflow::ExecutionPlan::Steps::PlanStep
    end
    plan_steps.all? { |plan_step| plan_step.state.must_equal :success }
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
