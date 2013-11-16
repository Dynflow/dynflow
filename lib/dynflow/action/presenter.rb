module Dynflow

  # This module is used for providing access to the results of the
  # action. It's used in ExecutionPlan#actions to provide access to
  # data of the actions in the execution plan.
  #
  # It also defines helper methods to extract usable data from the action itself,
  # as well as other actions involved in the execution plan. One action (usually the
  # main trigger, can use them to collect data across the whole execution_plan)
  module Action::Presenter

    def self.included(base)
      base.send(:attr_reader, :input)
      base.send(:attr_reader, :output)
      base.send(:attr_reader, :all_actions)
    end

    def self.load(execution_plan, action_id, involved_steps, all_actions)
      persistence_adapter = execution_plan.world.persistence.adapter
      attributes          = persistence_adapter.load_action(execution_plan.id,
                                                            action_id)
      raise ArgumentError, 'missing :class' unless attributes[:class]
      Action.constantize(attributes[:class]).presenter.new(attributes,
                                                           involved_steps,
                                                           all_actions)
    end

    def to_hash
      recursive_to_hash(action: action_class,
                        input:  input,
                        output: output)
    end

    # @param [Hash] attributes - the action attributes, usually loaded form persistence layer
    # @param [Array<ExecutionPlan::Steps::AbstractStep> - steps that operate on top of the action
    # @param [Array<Action::Presenter>] - array of all the actions involved in the execution plan
    #                                     with this action. Allows to access data from other actions
    def initialize(attributes, involved_steps, all_actions)
      @execution_plan_id = attributes[:execution_plan_id] || raise(ArgumentError, 'missing execution_plan_id')
      @id                = attributes[:id] || raise(ArgumentError, 'missing id')

      # TODO: use the involved_steps to provide summary state and error for the action
      @involved_steps    = involved_steps
      @all_actions       = all_actions

      indifferent_access_hash_variable_set :input, attributes[:input]
      indifferent_access_hash_variable_set :output, attributes[:output] || {}
    end

  end
end
