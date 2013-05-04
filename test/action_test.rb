require 'test_helper'

module Dynflow
  class ActionTest < Action

    output_format do
      param :id, String
    end

    def run
      output['id'] = input['name']
    end

  end

  describe 'running an action' do

    it 'executed the run method storing results to output attribute'do
      action = ActionTest.new('name' => 'zoo')
      action.run
      action.output.must_equal('id' => "zoo")
    end

  end
end
