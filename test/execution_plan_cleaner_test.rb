# frozen_string_literal: true

require_relative 'test_helper'
require 'mocha/minitest'

module Dynflow
  module ExecutionPlanCleanerTest
    describe ::Dynflow::Actors::ExecutionPlanCleaner do
      include Dynflow::Testing::Assertions
      include Dynflow::Testing::Factories
      include TestHelpers

      class SimpleAction < ::Dynflow::Action
        def plan; end
      end

      before do
        world.persistence.delete_execution_plans({})
      end

      let(:default_world) { WorldFactory.create_world }
      let(:age) { 10 }
      let(:world) do
        WorldFactory.create_world do |config|
          config.execution_plan_cleaner = proc do |world|
            ::Dynflow::Actors::ExecutionPlanCleaner.new(world, :max_age => age, **{})
          end
        end
      end
      let(:clock) { Testing::ManagedClock.new }

      it 'is disabled by default' do
        assert_nil default_world.execution_plan_cleaner
        _(world.execution_plan_cleaner)
          .must_be_instance_of ::Dynflow::Actors::ExecutionPlanCleaner
      end

      it 'periodically looks for old execution plans' do
        world.stub(:clock, clock) do
          _(clock.pending_pings.count).must_equal 0
          world.execution_plan_cleaner.core.ask!(:start)
          _(clock.pending_pings.count).must_equal 1
          world.persistence.expects(:find_old_execution_plans).returns([])
          world.persistence.expects(:delete_execution_plans).with(:uuid => [])
          clock.progress
          wait_for { clock.pending_pings.count == 1 }
        end
      end

      it 'cleans up old plans' do
        world.stub(:clock, clock) do
          world.execution_plan_cleaner.core.ask!(:start)
          _(clock.pending_pings.count).must_equal 1
          plans = (1..10).map { world.trigger SimpleAction }
                         .each { |plan| plan.finished.wait }
          world.persistence.find_execution_plans(:uuid => plans.map(&:id))
               .each do |plan|
            plan.instance_variable_set(:@ended_at, plan.ended_at - 15)
            plan.save
          end
          world.execution_plan_cleaner.core.ask!(:clean!)
          plans = world.persistence.find_execution_plans(:uuid => plans.map(&:id))
          _(plans.count).must_equal 0
        end
      end

      it 'leaves "new enough" plans intact' do
        world.stub(:clock, clock) do
          count = 10
          world.execution_plan_cleaner.core.ask!(:start)
          _(clock.pending_pings.count).must_equal 1
          plans = (1..10).map { world.trigger SimpleAction }
                         .each { |plan| plan.finished.wait }
          world.execution_plan_cleaner.core.ask!(:clean!)
          plans = world.persistence.find_execution_plans(:uuid => plans.map(&:id))
          _(plans.count).must_equal count
        end
      end
    end
  end
end
