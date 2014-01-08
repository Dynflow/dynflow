module Dynflow
  class Daemon
    include Algebrick::TypeCheck

    def initialize(listener, world, lock_file = nil)
      @listener  = Type! listener, Listeners::Abstract
      @world     = Type! world, World
      @lock_file = Type! lock_file, String, NilClass
    end

    def run
      with_lock_file do
        terminated = Future.new
        trap('SIGINT') { @world.terminate terminated }
        terminated.wait
      end
    end

    def with_lock_file(&block)
      if @lock_file
        raise "Lockfile #{@lock_file} is already present." if File.exist?(@lock_file)
        File.write(@lock_file, "Locked at #{Time.now} by process #{$$}\n")
      end
      block.call
    ensure
      File.delete(@lock_file) if @lock_file
    end
  end
end
