require 'test_helper'

module Dynflow

  describe Dispatcher do
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

    end

    class PromotionObserver < Action

      def self.subscribe
        Promotion
      end

    end

    class CloneRepo < Action

      input_format do
        param :name, String
      end

      output_format do
        param :id, String
      end

    end

    class ClonePackage < Action

      input_format do
        param :name, String
      end

      output_format do
        param :id, String
      end

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

    end

    it "builds the execution plan" do
      execution_plan = Promotion.plan(['zoo', 'foo'], ['elephant'])
      expected_plan =
        [
         CloneRepo.new('name' => 'zoo'),
         CloneRepo.new('name' => 'foo'),
         ClonePackage.new('name' => 'elephant'),
         YetAnotherAction.new('name' => 'elephant', 'hello' => 'world'),
         UpdateIndex.new('name' => 'elephant'),
         Promotion.new('actions' => 3) ,
         PromotionObserver.new('actions' => 3)
        ]
      execution_plan.must_equal expected_plan
    end

  end
end
