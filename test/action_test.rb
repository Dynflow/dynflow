require 'test_helper'

module Eventum
  class CloneRepo < Action

    output_format do
      param :id, String
    end

    def run
      output['id'] = input['name']
    end

  end

  class CloneRepoTest < ParticipantTestCase

    def test_action
      action = run_action(CloneRepo, {:name => "zoo"})
      assert_equal(action.output['id'], "zoo")
    end

  end
end
