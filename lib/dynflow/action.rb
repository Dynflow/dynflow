require 'active_support/inflector'

module Dynflow

  class Action < Serializable
    include Algebrick::TypeCheck

    require 'dynflow/action/format'
    extend Format

    require 'dynflow/action/progress'
    include Progress

    require 'dynflow/action/suspended'
    require 'dynflow/action/missing'

    require 'dynflow/action/plan_phase'
    require 'dynflow/action/flow_phase'
    require 'dynflow/action/run_phase'
    require 'dynflow/action/finalize_phase'

    def self.plan_phase
      @planning ||= self.generate_phase(PlanPhase)
    end

    def self.run_phase
      @running ||= self.generate_phase(RunPhase)
    end

    def self.finalize_phase
      @finishing ||= self.generate_phase(FinalizePhase)
    end

    # Override this to extend the phase classes
    def self.generate_phase(phase_module)
      Class.new(self) { include phase_module }
    end

    def self.phase?
      [PlanPhase, RunPhase, FinalizePhase].any? { |phase| self < phase }
    end

    def self.all_children
      children.
          inject(children) { |children, child| children + child.all_children }.
          select { |ch| !ch.phase? }
    end

    # FIND define subscriptions in world independent on action's classes,
    #   limited only by in/output formats
    # @return [nil, Class] a child of Action
    def self.subscribe
      nil
    end

    def self.attr_indifferent_access_hash(*names)
      attr_reader(*names)
      names.each do |name|
        define_method("#{name}=") { |v| indifferent_access_hash_variable_set name, v }
      end
    end

    def indifferent_access_hash_variable_set(name, value)
      is_kind_of! value, Hash
      instance_variable_set :"@#{name}", value.with_indifferent_access
    end

    def self.from_hash(hash, phase, *args)
      check_class_key_present hash
      raise ArgumentError, "unknown phase '#{phase}'" unless [:plan_phase, :run_phase, :finalize_phase].include? phase
      Action.constantize(hash[:class]).send(phase).new_from_hash(hash, *args)
    end

    attr_reader :world, :state, :execution_plan_id, :id, :plan_step_id, :run_step_id, :finalize_step_id, :error

    def initialize(attributes, world)
      raise "It's not expected to initialize this class directly, use phases." unless self.class.phase?

      is_kind_of! attributes, Hash

      @world             = is_kind_of! world, World
      self.state         = attributes[:state] || raise(ArgumentError, 'missing state')
      @execution_plan_id = attributes[:execution_plan_id] || raise(ArgumentError, 'missing execution_plan_id')
      @id                = attributes[:id] || raise(ArgumentError, 'missing id')
      @plan_step_id      = attributes[:plan_step_id]
      @run_step_id       = attributes[:run_step_id]
      @finalize_step_id  = attributes[:finalize_step_id]
      @error             = nil
    end

    def self.action_class
      # superclass because we run this from the phases of action class
      if phase?
        superclass
      else
        self
      end
    end

    def self.constantize(action_name)
      action_name.constantize
    rescue NameError
      Action::Missing.generate(action_name)
    end

    def action_logger
      world.action_logger
    end

    def action_class
      self.class.action_class
    end

    def to_hash
      recursive_to_hash class:             action_class.name,
                        execution_plan_id: execution_plan_id,
                        id:                id,
                        state:             state,
                        plan_step_id:      plan_step_id,
                        run_step_id:       run_step_id,
                        finalize_step_id:  finalize_step_id
    end

    # TODO add :running state to be able to detect it dieing in the middle of execution
    # TODO add STATE_TRANSITIONS an check it
    STATES = [:pending, :success, :suspended, :skipped, :error]

    # @api private
    # @return [Array<Fixnum>] - ids of steps referenced from action
    def required_step_ids(value = self.input)
      ret = case value
            when Hash
              value.values.map { |val| required_step_ids(val) }
            when Array
              value.map { |val| required_step_ids(val) }
            when ExecutionPlan::OutputReference
              value.step_id
            else
              # no reference hidden in this arg
            end
      return Array(ret).flatten.compact
    end

    protected

    def state=(state)
      raise "unknown state #{state}" unless STATES.include? state
      @state = state
    end

    # @override
    def plan(*args)
      if trigger
        # if the action is triggered by subscription, by default use the
        # input of parent action.
        # should be replaced by referencing the input from input format
        plan_self(input.merge(trigger.input))
      else
        # in this case, the action was triggered by plan_action. Use
        # the argument specified there.
        plan_self(*args)
      end
      self
    end

    def self.new_from_hash(hash, world)
      new(hash, world)
    end

    private

    def with_error_handling(&block)
      raise "wrong state #{self.state}" unless self.state == :pending

      begin
        block.call
      rescue => error
        action_logger.error error
        self.state = :error
        @error     = ExecutionPlan::Steps::Error.new(error.class.name, error.message, error.backtrace)
      end

      case self.state
      when :pending
        self.state = :success
      when :suspended, :error
      else
        raise "wrong state #{self.state}"
      end
    end

    def self.inherited(child)
      children << child
    end

    def self.children
      @children ||= []
    end
  end
end
