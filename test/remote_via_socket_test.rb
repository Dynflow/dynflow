require_relative 'test_helper'

describe 'remote communication' do

  let(:persistence_adapter) { Dynflow::PersistenceAdapters::Sequel.new('sqlite:/') }

  module Helpers
    def socket_path
      @socket_path ||= Dir.tmpdir + "/dynflow_remote_#{rand(1e30)}"
    end

    def logger_adapter
      WorldInstance.logger_adapter
    end

    def create_world
      Dynflow::SimpleWorld.new logger_adapter:      logger_adapter,
                               auto_terminate:      false,
                               persistence_adapter: persistence_adapter
    end

    def create_remote_world
      Dynflow::SimpleWorld.new(
          logger_adapter:      logger_adapter,
          auto_terminate:      false,
          persistence_adapter: persistence_adapter,
          executor:            -> remote_world do
            Dynflow::Executors::RemoteViaSocket.new(remote_world, socket_path)
          end)
    end

    def create_listener(world)
      Dynflow::Listeners::Socket.new world, socket_path, 0.05
    end

    def terminate(*terminable)
      terminable.each { |t| t.terminate.wait }
    end
  end

  include Helpers

  it 'raises when not connected' do
    remote_world = create_remote_world
    result       = remote_world.trigger Support::CodeWorkflowExample::Commit, 'sha'
    result.must_be :planned?
    result.wont_be :triggered?
    result.error.must_be_kind_of Dynflow::Error

    terminate remote_world
  end

  describe 'execute_planned_execution_plans' do
    specify do
      remote_world = create_remote_world
      result       = remote_world.trigger Support::CodeWorkflowExample::Commit, 'sha'
      result.must_be :planned?
      result.wont_be :triggered?
      result.error.must_be_kind_of Dynflow::Error

      remote_world.persistence.load_execution_plan(result.id).state.must_equal :planned

      world    = create_world
      listener = create_listener(world)

      # waiting until it starts executing
      assert(10.times do |i|
        state = world.persistence.load_execution_plan(result.id).state
        break :ok if [:running, :stopped].include? state
        puts 'retry'
        sleep 0.01 * i
      end == :ok)

      terminate remote_world, listener, world
    end
  end

  describe 'shutting down' do
    [:remote_world, :world, :listener].permutation.each do |order|
      it "works when in order #{order}" do
        objects = { world:        w = create_world,
                    listener:     create_listener(w),
                    remote_world: remote_world = create_remote_world }

        result = remote_world.trigger Support::CodeWorkflowExample::Commit, 'sha'
        result.must_be :planned?
        result.finished.value!.must_be_kind_of Dynflow::ExecutionPlan

        terminate *objects.values_at(*order)
        assert true, 'it has to reach this'
      end
    end

    it 'allows to work others' do
      world    = create_world
      listener = create_listener(world)
      rmw1     = create_remote_world
      rmw2     = create_remote_world

      [rmw1.trigger(Support::CodeWorkflowExample::Commit, 'sha').finished,
       rmw2.trigger(Support::CodeWorkflowExample::Commit, 'sha').finished].
          each(&:value!)

      terminate rmw1

      refute rmw1.trigger(Support::CodeWorkflowExample::Commit, 'sha').triggered?
      rmw2.trigger(Support::CodeWorkflowExample::Commit, 'sha').
          finished.value!.must_be_kind_of Dynflow::ExecutionPlan

      terminate rmw2, listener, world
    end

    it 'raises when disconnected while executing' do
      world        = create_world
      listener     = create_listener(world)
      remote_world = create_remote_world

      result = remote_world.trigger(Support::CodeWorkflowExample::Slow, 2)
      result.must_be :planned?

      terminate listener

      -> { result.finished.value! }.must_raise Dynflow::Future::FutureFailed
      terminate remote_world, world
    end

  end

  it 'restarts' do
    world        = create_world
    listener     = create_listener(world)
    remote_world = create_remote_world

    remote_world.trigger(Support::CodeWorkflowExample::Commit, 'sha').finished.value!

    terminate listener
    Thread.pass while remote_world.executor.connected?
    listener = create_listener world
    Thread.pass until remote_world.executor.connected?

    remote_world.trigger(Support::CodeWorkflowExample::Commit, 'sha').finished.value!

    terminate listener, world
    Thread.pass while remote_world.executor.connected?
    world    = create_world
    listener = create_listener world
    Thread.pass until remote_world.executor.connected?

    remote_world.trigger(Support::CodeWorkflowExample::Commit, 'sha').finished.value!

    terminate listener, world, remote_world
  end

  describe '#connected?' do
    specify do
      remote_world = create_remote_world

      remote_world.executor.connected?.must_equal false

      world    = create_world
      listener = create_listener world

      remote_world.executor.connected?.must_equal true

      terminate listener, world, remote_world
    end
  end
end
