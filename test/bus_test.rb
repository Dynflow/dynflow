require 'test_helper'
require 'set'

module Eventum

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

  class BusTest < BusTestCase

    def event
      Promotion.new('repositories' =>
                    [{'name' => 'zoo'},
                     {'name' => 'foo'}])
    end

    def test_optimistic_case
      expect_input(CloneRepo, {'name' => 'zoo'}, {'id' => '123'})
      expect_input(CloneRepo, {'name' => 'foo'}, {'id' => '456'})
      first_action, second_action = assert_scenario

      assert_equal({'name' => 'zoo'}, first_action.input)
      assert_equal({'id' => '123'},   first_action.output)
      assert_equal({'name' => 'foo'}, second_action.input)
      assert_equal({'id' => '456'},   second_action.output)
    end

  end
end
