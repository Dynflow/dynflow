require 'active_support/inflector'
require 'forwardable'
module Dynflow
  class Bus

    class << self
      extend Forwardable

      def_delegators :impl, :wait_for, :process, :trigger, :finalize

      def impl
        @impl ||= Bus::MemoryBus.new
      end
      attr_writer :impl
    end

    def prepare_execution_plan(action_class, *args)
      action_class.plan(*args)
    end

    # provided block yields every action before and after processing
    def run_execution_plan(execution_plan)
      failure = false
      execution_plan.actions.map do |action|
        next action if failure
        yield(:before, action) if block_given?
        begin
          action = self.process(action)
          action.status = 'success'
        rescue Exception => e
          action.output['error'] = {'exception' => e.class.name, 'message' => e.message}
          action.status = 'error'
          failure = true
        end
        yield(:after, action) if block_given?
        action
      end
    end

    def finalize(outputs)
      if outputs.any? { |action| ['pending', 'error'].include?(action.status) }
        return false
      end
      outputs.each do |action|
        if action.respond_to?(:finalize)
          action.finalize(outputs)
        end
      end
    end

    def process(action)
      # TODO: here goes the message validation
      action.run if action.respond_to?(:run)
      return action
    end

    def wait_for(*args)
      raise NotImplementedError, 'Abstract method'
    end

    def logger
      @logger ||= Dynflow::Logger.new(self.class)
    end

    class MemoryBus < Bus

      def trigger(action_class, *args)
        execution_plan = prepare_execution_plan(action_class, *args)
        outputs = run_execution_plan(execution_plan)
        self.finalize(outputs)
      end

    end

    # uses Rails API for db features
    # encapsulates the planning and finalization phase into
    class RailsBus < Bus

      def trigger(action_class, *args)
        execution_plan = nil
        ActiveRecord::Base.transaction do
          execution_plan = prepare_execution_plan(action_class, *args)
        end
        journal = create_journal(action_class, execution_plan)
        outputs = run_execution_plan(execution_plan) do |phase, action|
          if phase == :after
            update_journal(journal, action)
          end
        end
        ActiveRecord::Base.transaction do
          self.finalize(outputs)
        end
        update_journal_status(journal, 'finished')
      end

      # performs the planning phase of an action, but rollbacks any db
      # changes done in this phase. Returns the resulting execution
      # plan. Suitable for debugging.
      def preview_execution_plan(action_class, *args)
        ActiveRecord::Base.transaction do
          execution_plan = prepare_execution_plan(action_class, *args)
          raise ActiveRecord::Rollback
        end
        return execution_plan
      end

      def create_journal(action_class, execution_plan)
        journal = Dynflow::Journal.create! do |journal|
          journal.originator = action_class.name
          journal.status = 'running'
        end
        execution_plan.actions.each do |action|
          journal_item = journal.journal_items.create do |journal_item|
            journal_item.action = action
          end
          action.journal_item_id = journal_item.id
        end
        return journal
      end

      def update_journal(journal, action)
        JournalItem.find(action.journal_item_id).
          update_attributes(:action => action)
      end

      def update_journal_status(journal, status)
        journal.update_attributes!(:status => status)
      end

    end

  end
end
