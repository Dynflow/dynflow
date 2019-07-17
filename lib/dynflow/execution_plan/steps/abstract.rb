module Dynflow
  module ExecutionPlan::Steps
    class Abstract < Serializable
      include Algebrick::TypeCheck
      include Stateful

      attr_reader :execution_plan_id, :id, :state, :action_class, :action_id, :world, :started_at,
                  :ended_at, :execution_time, :real_time, :queue
      attr_accessor :error

      # rubocop:disable Metrics/ParameterLists
      def initialize(execution_plan_id,
                     id,
                     state,
                     action_class,
                     action_id,
                     error,
                     world,
                     started_at      = nil,
                     ended_at        = nil,
                     execution_time  = 0.0,
                     real_time       = 0.0,
                     progress_done   = nil,
                     progress_weight = nil,
                     queue           = nil)

        @id                = id || raise(ArgumentError, 'missing id')
        @execution_plan_id = Type! execution_plan_id, String
        @world             = Type! world, World
        @error             = Type! error, ExecutionPlan::Steps::Error, NilClass
        @started_at        = Type! started_at, Time, NilClass
        @ended_at          = Type! ended_at, Time, NilClass
        @execution_time    = Type! execution_time, Numeric
        @real_time         = Type! real_time, Numeric

        @progress_done     = Type! progress_done, Numeric, NilClass
        @progress_weight   = Type! progress_weight, Numeric, NilClass

        @queue             = Type! queue, Symbol, NilClass

        self.state = state.to_sym

        Child! action_class, Action
        @action_class = action_class

        @action_id = action_id || raise(ArgumentError, 'missing action_id')
      end
      # rubocop:enable Metrics/ParameterLists

      def ==(other)
        other.class == self.class && other.execution_plan_id == self.execution_plan_id && other.id == self.id
      end

      def action_logger
        @world.action_logger
      end

      def phase
        raise NotImplementedError
      end

      def mark_to_skip
        raise NotImplementedError
      end

      def persistence
        world.persistence
      end

      def save
        persistence.save_step(self)
      end

      def self.states
        @states ||= [:scheduling, :pending, :running, :success, :suspended, :skipping, :skipped, :error, :cancelled]
      end

      def execute(*args)
        raise NotImplementedError
      end

      def to_s
        "#<#{self.class.name}:#{execution_plan_id}:#{id}>"
      end

      def to_hash
        recursive_to_hash execution_plan_uuid: execution_plan_id,
                          id:                  id,
                          state:               state,
                          class:               self.class.to_s,
                          action_class:        action_class.to_s,
                          action_id:           action_id,
                          error:               error,
                          started_at:          started_at,
                          ended_at:            ended_at,
                          execution_time:      execution_time,
                          real_time:           real_time,
                          progress_done:       progress_done,
                          progress_weight:     progress_weight,
                          queue:               queue
      end

      def progress_done
        default_progress_done || @progress_done || 0
      end

      # in specific states it's clear what progress the step is in
      def default_progress_done
        case self.state
        when :success, :skipped
          1
        when :pending
          0
        end
      end

      def progress_weight
        @progress_weight || 0 # 0 means not calculated yet
      end

      attr_writer :progress_weight # to allow setting the weight from planning

      # @return [Action] in presentation mode, intended for retrieving: progress information,
      # details, human outputs, etc.
      def action(execution_plan)
        world.persistence.load_action_for_presentation(execution_plan, action_id, self)
      end

      def skippable?
        self.state == :error
      end

      def cancellable?
        false
      end

      def with_sub_plans?
        false
      end

      protected

      def self.new_from_hash(hash, execution_plan_id, world)
        check_class_matching hash
        new(execution_plan_id,
            hash[:id],
            hash[:state],
            Action.constantize(hash[:action_class]),
            hash[:action_id],
            hash_to_error(hash[:error]),
            world,
            string_to_time(hash[:started_at]),
            string_to_time(hash[:ended_at]),
            hash[:execution_time].to_f,
            hash[:real_time].to_f,
            hash[:progress_done].to_f,
            hash[:progress_weight].to_f,
            (hash[:queue] && hash[:queue].to_sym))
      end

      private

      def with_meta_calculation(action, &block)
        start       = Time.now.utc
        @started_at ||= start
        block.call
      ensure
        calculate_progress(action)
        @ended_at = Time.now.utc
        current_execution_time = @ended_at - start
        @execution_time += current_execution_time
        @real_time       = @ended_at - @started_at
        update_step_telemetry(current_execution_time)
      end

      def calculate_progress(action)
        @progress_done, @progress_weight = action.calculated_progress
        if @progress_done.is_a?(Float) && !@progress_done.finite?
          action_logger.error("Unexpected progress value #{@progress_done} for step #{execution_plan_id}##{id}")
          @progress_done = 0
        end
      end

      def update_step_telemetry(current_execution_time)
        Dynflow::Telemetry.with_instance do |t|
          if [:success, :skipped].include?(state)
            t.observe_histogram(:dynflow_step_real_time,
                                real_time * 1000,
                                :action => action_class.to_s, :phase => phase.to_s_humanized)
          end
          t.observe_histogram(:dynflow_step_execution_time,
                              current_execution_time * 1000,
                              :action => action_class.to_s, :phase => phase.to_s_humanized)
        end
      end
    end
  end
end
