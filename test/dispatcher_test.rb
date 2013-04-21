require 'test_helper'

module Eventum


  describe Dispatcher do
    class Promotion < Event
      format do
        param :repositories, Array do
          param :name, String
        end
        param :packages, Array do
          param :name, String
        end
      end
    end

    class CloneRepo < Action

      def self.subscribe
        { Promotion => :repositories }
      end

      output_format do
        param :id, String
      end

      def run
        output['id'] = input['name']
      end

    end

    class ClonePackage < Action

      def self.subscribe
        { Promotion => :packages }
      end

      def self.require
        CloneRepo
      end

      output_format do
        param :id, String
      end

      def run
        output['id'] = input['name']
      end

    end

    def event
      Promotion.new('repositories' =>
                    [{'name' => 'zoo'},
                     {'name' => 'foo'}])

    end

    it "builds the execution plan" do
      execution_plan = Dispatcher.execution_plan_for(event)
      expected_plan =
        [
         [CloneRepo, {'name' => 'zoo'}],
         [CloneRepo, {'name' => 'foo'}]
        ]
      execution_plan.must_equal expected_plan
    end

  end
end
