require 'active_support/inflector'

module Dynflow
  class Action < Serializable
    include Algebrick::TypeCheck

    require 'dynflow/action/format'
    extend Format

    require 'dynflow/action/plan_phase'
    require 'dynflow/action/run_phase'
    require 'dynflow/action/final_phase'

    def self.plan_phase
      @planning ||= Class.new(self) do
        include PlanPhase
        ignored_child!
      end
    end

    def self.run_phase
      @running ||= Class.new(self) do
        include RunPhase
        ignored_child!
      end
    end

    def self.final_phase
      @finishing ||= Class.new(self) do
        include FinalPhase
        ignored_child!
      end
    end

    def self.all_children
      children.
          inject(children) { |children, child| children + child.all_children }.
          select { |ch| not ch.ignored_child? }
    end

    # @return [nil, Class] a child of Action
    def self.subscribe
      nil
    end

    def self.attr_indifferent_access_hash(*names)
      attr_reader(*names)
      names.each do |name|
        define_method "#{name}=" do |v|
          is_kind_of! v, Hash
          instance_variable_set :"@#{name}", v.with_indifferent_access
        end
      end
    end

    attr_reader :world, :state, :id, :plan_step_id, :run_step_id, :finalize_step_id
    attr_indifferent_access_hash :error

    def initialize(attributes, world)
      unless [PlanPhase, RunPhase, FinalPhase].any? { |phase| self.is_a? phase }
        raise "It's not expected to initialize this class directly"
      end

      is_kind_of! attributes, Hash

      @world            = is_kind_of! world, World
      self.state       = attributes[:state] || raise(ArgumentError, 'missing state')
      @id               = attributes[:id] || raise(ArgumentError, 'missing id')
      @plan_step_id     = attributes[:plan_step_id]
      @run_step_id      = attributes[:run_step_id]
      @finalize_step_id = attributes[:finalize_step_id]
      self.error        = attributes[:error] || {}
    end

    def action_class
      # superclass because we run this from the phases of action class
      self.class.superclass
    end

    def to_hash
      { class:            action_class.name,
        id:               id,
        error:            error,
        plan_step_id:     plan_step_id,
        run_step_id:      run_step_id,
        finalize_step_id: finalize_step_id }
    end

    STATES = [:pending, :success, :suspended, :error]

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

    private

    def with_error_handling(&block)
      begin
        block.call
        self.state = :success
      rescue => e
        self.state = :error
        self.error  = { exception: e.class.name,
                        message:   e.message,
                        backtrace: e.backtrace }
      end
    end

    def self.ignored_child?
      !!@ignored_child
    end

    def self.inherited(child)
      children << child
    end

    def self.children
      @children ||= []
    end

    def self.ignored_child!
      @ignored_child = true
    end
  end
end
