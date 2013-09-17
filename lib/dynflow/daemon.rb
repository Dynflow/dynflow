module Dynflow
  class Daemon
    include Algebrick::TypeCheck

    def initialize(listener, world)
      @listener = is_kind_of! listener, Listeners::Abstract
      @world    = is_kind_of! world, World
    end

    def run
      terminated = Future.new
      trap('SIGINT') { @world.terminate! terminated }
      terminated.wait
    end
  end
end
