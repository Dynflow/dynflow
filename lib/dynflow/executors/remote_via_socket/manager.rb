module Dynflow
  module Executors
    class RemoteViaSocket < Abstract

      class Manager
        include Algebrick::TypeCheck

        def initialize(persistence)
          @world            = Type! persistence, Dynflow::World
          @last_id          = 0
          @finished_futures = {}
          @accepted_futures = {}
        end

        def add(future)
          id                    = @last_id += 1
          @finished_futures[id] = future
          @accepted_futures[id] = accepted = Future.new
          return id, accepted
        end

        def accepted(id)
          @accepted_futures.delete(id).resolve true
        end

        def failed(id, error)
          @finished_futures.delete id
          @accepted_futures.delete(id).resolve Dynflow::Error.new(error)
        end

        def finished(id, uuid)
          @finished_futures.delete(id).resolve @world.persistence.load_execution_plan(uuid)
        end

        def empty?
          @finished_futures.empty?
        end
      end
    end
  end
end
