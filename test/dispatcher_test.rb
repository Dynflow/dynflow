require 'test_helper'

module Eventum

  describe Dispatcher do
    class Promotion < Action

      def plan(repo_names, package_names)
        repo_names.each do |repo_name|
          plan_action(CloneRepo, {'name' => repo_name})
        end

        package_names.each do |package_name|
          plan_action(ClonePackage, {'name' => package_name})
        end
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
        param :hello, String
      end

      output_format do
        param :hello, String
      end

    end

    it "builds the execution plan" do
      execution_plan = Promotion.plan(['zoo', 'foo'], ['elephant'])
      expected_plan =
        [
         [CloneRepo, {'name' => 'zoo'}],
         [CloneRepo, {'name' => 'foo'}],
         [ClonePackage, {'name' => 'elephant'}],
         [YetAnotherAction, {'hello' => 'world'}],
         [UpdateIndex, {'name' => 'elephant'}],
        ]
      execution_plan.must_equal expected_plan
    end

  end
end
