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
        @memory_checked_callback = options[:memory_checked_callback]
        @memory_limit_exceeded_callback = options[:memory_limit_exceeded_callback]
        set_timer options[:initial_wait] || @polling_interval
      end

      def check_memory_state
        current_memory = @memory_info_provider.bytes
        if current_memory > @memory_limit
          @memory_limit_exceeded_callback.call(current_memory, @memory_limit) if @memory_limit_exceeded_callback
          # terminate the world and stop polling
          world.terminate
        else
          @memory_checked_callback.call(current_memory, @memory_limit) if @memory_checked_callback
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
