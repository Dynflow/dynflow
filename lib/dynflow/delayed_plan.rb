module Dynflow
  class DelayedPlan < Serializable

    include Algebrick::TypeCheck

    attr_reader :execution_plan_uuid, :start_before
    attr_accessor :frozen, :start_at

    def initialize(world, execution_plan_uuid, start_at, start_before, args_serializer, frozen)
      @world               = Type! world, World
      @execution_plan_uuid = Type! execution_plan_uuid, String
      @start_at            = Type! start_at, Time, NilClass
      @start_before        = Type! start_before, Time, NilClass
      @args_serializer     = Type! args_serializer, Serializers::Abstract
      @frozen              = Type! frozen, Algebrick::Types::Boolean
    end

    def execution_plan
      @execution_plan ||= @world.persistence.load_execution_plan(@execution_plan_uuid)
    end

    def plan
      execution_plan.root_plan_step.load_action
      execution_plan.generate_action_id
      execution_plan.generate_step_id
      execution_plan.plan(*@args_serializer.perform_deserialization!)
    end

    def timeout
      error("Execution plan could not be started before set time (#{@start_before})", 'timeout')
    end

    def error(message, history_entry = nil)
      execution_plan.root_plan_step.state = :error
      execution_plan.root_plan_step.error = ::Dynflow::ExecutionPlan::Steps::Error.new(message)
      execution_plan.root_plan_step.save
      execution_plan.execution_history.add history_entry, @world.id unless history_entry.nil?
      execution_plan.update_state :stopped
    end

    def cancel
      execution_plan.root_plan_step.state = :cancelled
      execution_plan.root_plan_step.save
      execution_plan.execution_history.add "Delayed task cancelled", @world.id
      execution_plan.update_state :stopped
      @world.persistence.delete_delayed_plans(:execution_plan_uuid => @execution_plan_uuid)
      return true
    end

    def execute(future = Concurrent::Promises.resolvable_future)
      @world.execute(@execution_plan_uuid, future)
      ::Dynflow::World::Triggered[@execution_plan_uuid, future]
    end

    def to_hash
      recursive_to_hash :execution_plan_uuid => @execution_plan_uuid,
                        :start_at            => @start_at,
                        :start_before        => @start_before,
                        :serialized_args     => @args_serializer.serialized_args,
                        :args_serializer     => @args_serializer.class.name,
                        :frozen              => @frozen
    end

    # Retrieves arguments from the serializer
    #
    # @return [Array] array of the original arguments
    def args
      @args_serializer.perform_deserialization! if @args_serializer.args.nil?
      @args_serializer.args
    end

    # @api private
    def self.new_from_hash(world, hash, *args)
      serializer = Utils.constantize(hash[:args_serializer]).new(nil, hash[:serialized_args])
      self.new(world,
               hash[:execution_plan_uuid],
               string_to_time(hash[:start_at]),
               string_to_time(hash[:start_before]),
               serializer,
               hash[:frozen] || false)
    rescue NameError => e
      error(e.message)
    end
  end
end
