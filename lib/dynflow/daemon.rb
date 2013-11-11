module Dynflow
  class Daemon
    include Algebrick::TypeCheck

    def initialize(listener, world, lock_file = nil)
      @listener  = is_kind_of! listener, Listeners::Abstract
      @world     = is_kind_of! world, World
      @lock_file = is_kind_of! lock_file, String, NilClass
    end

    def run
      with_lock_file do
        terminated = Future.new
        trap('SIGINT') { @world.terminate! terminated }
        terminated.wait
      end
    end

    def with_lock_file(&block)
      if @lock_file
        raise "Lockfile #{@lock_file} is already present." if File.exist?(@lock_file)
        File.write(@lock_file, "Locked at #{Time.now}")
      end
      block.call
    ensure
      File.delete(@lock_file) if @lock_file
    end
  end
end
