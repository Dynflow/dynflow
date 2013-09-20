module Dynflow
  module ExecutionPlan::Steps
    class Abstract < Serializable
      include Algebrick::TypeCheck

      attr_reader :execution_plan_id, :id, :state, :action_class, :action_id, :world, :started_at,
                  :ended_at, :execution_time, :real_time
      attr_accessor :error
      private :error=

      def initialize(execution_plan_id,
          id,
          state,
          action_class,
          action_id,
          error,
          world,
          started_at = nil,
          ended_at = nil,
          execution_time = 0.0,
          real_time = 0.0)

        @id                = id || raise(ArgumentError, 'missing id')
        @execution_plan_id = is_kind_of! execution_plan_id, String
        @world             = is_kind_of! world, World
        @error             = is_kind_of! error, ExecutionPlan::Steps::Error, NilClass
        @started_at        = is_kind_of! started_at, Time, NilClass
        @ended_at          = is_kind_of! ended_at, Time, NilClass
        @execution_time    = is_kind_of! execution_time, Float
        @real_time         = is_kind_of! real_time, Float

        if state.is_a?(String) && STATES.map(&:to_s).include?(state)
          self.state = state.to_sym
        else
          self.state = state
        end

        is_kind_of! action_class, Class
        raise ArgumentError, 'action_class is not an child of Action' unless action_class < Action
        raise ArgumentError, 'action_class must not be phase' if action_class.phase?
        @action_class = action_class

        @action_id = action_id || raise(ArgumentError, 'missing action_id')
      end

      def phase
        raise NotImplementedError
      end

      def persistence
        world.persistence
      end

      # TODO this is called allover the place, it should be unified to be called automatically after each change
      def save
        persistence.save_step(self)
      end

      STATES = Action::STATES

      def state=(state)
        raise "unknown state #{state}" unless STATES.include? state
        @state = state
      end

      def execute(*args)
        raise NotImplementedError
      end

      def to_hash
        recursive_to_hash id:             id,
                          state:          state,
                          class:          self.class.to_s,
                          action_class:   action_class.to_s,
                          action_id:      action_id,
                          error:          error,
                          started_at:     time_to_str(started_at),
                          ended_at:       time_to_str(ended_at),
                          execution_time: execution_time,
                          real_time:      real_time
      end

      protected

      def self.new_from_hash(hash, execution_plan_id, world)
        check_class_matching hash
        new execution_plan_id,
            hash[:id],
            hash[:state],
            hash[:action_class].constantize,
            hash[:action_id],
            hash_to_error(hash[:error]),
            world,
            string_to_time(hash[:started_at]),
            string_to_time(hash[:ended_at]),
            hash[:execution_time],
            hash[:real_time]
      end

      private

      def with_time_calculation(&block)
        start       = Time.now
        @started_at ||= start
        block.call
      ensure
        @ended_at       = Time.now
        @execution_time += @ended_at - start
        @real_time      = @ended_at - @started_at
      end
    end
  end
end
