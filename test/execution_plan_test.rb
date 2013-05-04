require 'test_helper'

module Dynflow
  module ExecutionPlanTest
    describe ExecutionPlan do
      class Promotion < Action

        def plan(repo_names, package_names)
          repo_names.each do |repo_name|
            plan_action(CloneRepo, {'name' => repo_name})
          end

          package_names.each do |package_name|
            plan_action(ClonePackage, {'name' => package_name})
          end

          plan_self('actions' => repo_names.size + package_names.size)
        end

        input_format do
          param :actions, Integer
        end

        def run; end

      end

      class PromotionObserver < Action

        def self.subscribe
          Promotion
        end

        def run; end

      end

      class CloneRepo < Action

        input_format do
          param :name, String
        end

        output_format do
          param :id, String
        end

        def run; end

      end

      class ClonePackage < Action

        input_format do
          param :name, String
        end

        output_format do
          param :id, String
        end

        def run; end

      end

      class UpdateIndex < Action

        def self.subscribe
          ClonePackage
        end

        def plan(input)
          plan_action(YetAnotherAction, {'hello' => 'world'})
          super
        end

        output_format do
          param :indexed_name, String
        end

        def run; end

      end

      class YetAnotherAction < Action

        input_format do
          param :name, String
          param :hello, String
        end

        output_format do
          param :hello, String
        end

        def plan(arg)
          plan_self(input.merge(arg))
        end

        def run; end

      end

      it "builds the execution plan" do
        execution_plan = Promotion.plan(['zoo', 'foo'], ['elephant'])
        expected_plan_actions =
          [
           CloneRepo.new('name' => 'zoo'),
           CloneRepo.new('name' => 'foo'),
           ClonePackage.new('name' => 'elephant'),
           YetAnotherAction.new('name' => 'elephant', 'hello' => 'world'),
           UpdateIndex.new('name' => 'elephant'),
           Promotion.new('actions' => 3) ,
           PromotionObserver.new('actions' => 3)
          ]
        execution_plan.run_steps.map(&:action).must_equal expected_plan_actions
      end

    end
  end
end
