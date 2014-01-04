module Dynflow
  class Middleware
    require 'dynflow/middleware/action'
    require 'dynflow/middleware/resolver'

    def initialize
      @actions_stacks = Hash.new do |h, k|
        h[k] = []
      end
    end

  end
end
