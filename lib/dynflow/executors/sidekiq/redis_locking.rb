module Dynflow
  module Executors
    module Sidekiq
      module RedisLocking
        REDIS_LOCK_KEY = 'dynflow_orchestrator_uuid'
        REDIS_LOCK_TTL = 60
        REDIS_LOCK_POLL_INTERVAL = 15

        ACQUIRE_OK = 0
        ACQUIRE_MISSING = 1
        ACQUIRE_TAKEN = 2

        RELEASE_SCRIPT = <<~LUA
          if redis.call("get", KEYS[1]) == ARGV[1] then
            redis.call("del", KEYS[1])
          end
          return #{ACQUIRE_OK}
        LUA

        REACQUIRE_SCRIPT = <<~LUA
          if redis.call("exists", KEYS[1]) == 1 then
            local owner = redis.call("get", KEYS[1])
            if owner == ARGV[1] then
              redis.call("set", KEYS[1], ARGV[1], "XX", "EX", #{REDIS_LOCK_TTL})
              return #{ACQUIRE_OK}
            else
              return #{ACQUIRE_TAKEN}
            end
          else
            redis.call("set", KEYS[1], ARGV[1], "NX", "EX", #{REDIS_LOCK_TTL})
            return #{ACQUIRE_MISSING}
          end
        LUA

        def release_orchestrator_lock
          ::Sidekiq.redis { |conn| conn.eval RELEASE_SCRIPT, [REDIS_LOCK_KEY], [@world.id] }
        end

        def wait_for_orchestrator_lock
          mode = nil
          loop do
            active = ::Sidekiq.redis do |conn|
              conn.set(REDIS_LOCK_KEY, @world.id, :ex => REDIS_LOCK_TTL, :nx => true)
            end
            break if active
            if mode.nil?
              mode = :passive
              @logger.info('Orchestrator lock already taken, entering passive mode.')
            end
            sleep REDIS_LOCK_POLL_INTERVAL
          end
          @logger.info('Acquired orchestrator lock, entering active mode.')
        end

        def reacquire_orchestrator_lock
          case ::Sidekiq.redis { |conn| conn.eval REACQUIRE_SCRIPT, [REDIS_LOCK_KEY], [@world.id] }
          when ACQUIRE_MISSING
            @logger.error('The orchestrator lock was lost, reacquired')
          when ACQUIRE_TAKEN
            owner = ::Sidekiq.redis { |conn| conn.get REDIS_LOCK_KEY }
            @logger.fatal("The orchestrator lock was stolen by #{owner}, aborting.")
            Process.kill('INT', Process.pid)
          end
        end
      end
    end
  end
end
