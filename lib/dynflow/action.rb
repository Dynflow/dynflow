module Dynflow
  class Action < Serializable
    include Algebrick::TypeCheck

    require 'dynflow/action/format'
    extend Format

    require 'dynflow/action/planning'
    require 'dynflow/action/running'
    require 'dynflow/action/finalizing'

    def self.planning
      @planning ||= Class.new(self) { include Planning; ignored_child! }
    end

    def self.running
      @running ||= Class.new(self) { include Running; ignored_child! }
    end

    def self.finalizing
      @finishing ||= Class.new(self) { include Finalizing; ignored_child! }
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

    attr_reader :world, :status, :id

    def initialize(world, status, id)
      @world      = is_kind_of! world, Bus
      @id         = id
      self.status = status
    end

    def to_hash
      { class: self.class.to_s }
    end

    STATES = [:pending, :success, :suspended, :error]

    protected

    def status=(status)
      raise "unknown state #{status}" unless STATES.include? status
      @status = status
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
        plan_self
      end
      self
    end

    private

    def with_error_handling(&block)
      begin
        block.call
        self.status = :success
      rescue => e
        self.status = :error
        self.error 'exception' => e.class.name,
                   'message'   => e.message,
                   'backtrace' => e.backtrace
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
