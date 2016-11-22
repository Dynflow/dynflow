require 'get_process_mem'

module Dynflow
  module Watchers
    class MemoryConsumptionWatcher

      attr_reader :memory_limit, :world

      def initialize(world, memory_limit, options)
        @memory_limit = memory_limit
        @world = world
        @polling_interval = options[:polling_interval] || 60
        @memory_info_provider = options[:memory_info_provider] || GetProcessMem.new
        set_timer options[:initial_wait] || @polling_interval
      end

      def check_memory_state
        if @memory_info_provider.bytes > @memory_limit
          # terminate the world and stop polling
          world.terminate
        else
          # memory is under the limit - keep waiting
          set_timer
        end
      end

      def set_timer(interval = @polling_interval)
        @world.clock.ping(self, interval, nil, :check_memory_state)
      end
    end
  end
end
