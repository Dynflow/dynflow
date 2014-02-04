require 'active_support/inflector'

module Dynflow

  # TODO unify phases into one class, check what can be called in what phase at runtime
  class Action < Serializable
    include Algebrick::TypeCheck
    include Algebrick::Matching

    require 'dynflow/action/format'
    extend Format

    extend Middleware::Action

    require 'dynflow/action/progress'
    include Progress

    require 'dynflow/action/suspended'
    require 'dynflow/action/missing'

    require 'dynflow/action/plan_phase'
    require 'dynflow/action/flow_phase'
    require 'dynflow/action/run_phase'
    require 'dynflow/action/finalize_phase'

    require 'dynflow/action/presenter'
    require 'dynflow/action/polling'
    require 'dynflow/action/cancellable_polling'

    # Override this to extend the phase classes
    def self.phase_modules
      { plan_phase:     [PlanPhase],
        run_phase:      [RunPhase],
        finalize_phase: [FinalizePhase],
        presenter:      [Presenter] }.freeze
    end

    phase_modules.each do |phase_name, _|
      define_singleton_method phase_name do
        instance_variable_get :"@#{phase_name}" or
            instance_variable_set :"@#{phase_name}", __send__("create_#{phase_name}")
      end

      define_singleton_method "create_#{phase_name}" do
        generate_phase(*phase_modules[phase_name])
      end
    end

    def self.generate_phase(*modules)
      Class.new(self) { modules.each { |m| include m } }
    end

    def self.phase?
      [PlanPhase, RunPhase, FinalizePhase, Presenter].any? { |phase| self < phase }
    end

    def self.all_children
      #noinspection RubyArgCount
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
      Type! value, Hash
      instance_variable_set :"@#{name}", value.with_indifferent_access
    end

    def self.from_hash(hash, phase, *args)
      check_class_key_present hash
      raise ArgumentError, "unknown phase '#{phase}'" unless [:plan_phase, :run_phase, :finalize_phase].include? phase
      Action.constantize(hash[:class]).send(phase).new_from_hash(hash, *args)
    end

    attr_reader :world, :execution_plan_id, :id, :plan_step_id, :run_step_id, :finalize_step_id

    def initialize(attributes, world)
      raise "It's not expected to initialize this class directly, use phases." unless self.class.phase?

      Type! attributes, Hash

      @world             = Type! world, World
      @step              = Type! attributes[:step], ExecutionPlan::Steps::Abstract
      @execution_plan_id = attributes[:execution_plan_id] || raise(ArgumentError, 'missing execution_plan_id')
      @id                = attributes[:id] || raise(ArgumentError, 'missing id')
      @plan_step_id      = attributes[:plan_step_id]
      @run_step_id       = attributes[:run_step_id]
      @finalize_step_id  = attributes[:finalize_step_id]
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
                        plan_step_id:      plan_step_id,
                        run_step_id:       run_step_id,
                        finalize_step_id:  finalize_step_id
    end

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

    def state
      @step.state
    end

    def error
      @step.error
    end

    protected

    def state=(state)
      @world.logger.debug "step #{execution_plan_id}:#{@step.id} #{self.state} >> #{state}"
      @step.state = state
    end

    def save_state
      @step.save
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

    ERROR = Object.new

    # DSL to terminate action execution and set it to error
    def error!(error)
      set_error(error)
      throw ERROR
    end

    def with_error_handling(&block)
      raise "wrong state #{self.state}" unless self.state == :running

      begin
        catch(ERROR) { block.call }
      rescue Exception => error
        set_error(error)
        # reraise low-level exceptions
        raise error unless Type? error, StandardError, ScriptError
      end

      case self.state
      when :running
        self.state = :success
      when :suspended, :error
      else
        raise "wrong state #{self.state}"
      end
    end

    def set_error(error)
      Type! error, Exception, String
      action_logger.error error
      self.state  = :error
      @step.error = if error.is_a?(String)
                      ExecutionPlan::Steps::Error.new(nil, error, nil)
                    else
                      ExecutionPlan::Steps::Error.new(error.class.name, error.message, error.backtrace)
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
