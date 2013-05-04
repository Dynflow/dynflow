require 'active_support/inflector'
require 'forwardable'
module Dynflow
  class Bus

    class << self
      extend Forwardable

      def_delegators :impl, :trigger, :resume, :skip, :preview_execution_plan

      def impl
        @impl ||= Bus::MemoryBus.new
      end
      attr_writer :impl
    end

    # Entry point for running an action
    def trigger(action_class, *args)
      execution_plan = in_transaction_if_possible do
        prepare_execution_plan(action_class, *args)
      end
      persist_plan_if_possible(action_class, execution_plan)
      return execute(execution_plan)
    end

    def prepare_execution_plan(action_class, *args)
      action_class.plan(*args)
    end

    # execution and finalizaition. Usable for resuming paused plan
    # as well as starting from scratch
    def execute(execution_plan)
      run_execution_plan(execution_plan)
      in_transaction_if_possible do
        unless self.finalize(execution_plan)
          rollback_transaction
        end
      end
      execution_plan.persist
      return execution_plan
    end

    alias_method :resume, :execute

    def skip(action)
      action.status = 'skipped'
    end

    def finalize_skip(action)
      action.status = 'finalize_skipped'
    end

    # return true if everyting worked fine
    def finalize(execution_plan)
      failure = false
      if execution_plan.actions.any? { |action| ['pending', 'error'].include?(action.status) }
        failure = true
      else
        execution_plan.actions.each do |action|
          break if failure
          next if %w[skipped finalize_skipped].include?(action.status)

          if action.respond_to?(:finalize)
            begin
              action.finalize(execution_plan.actions)
            rescue Exception => e
              action.finalize_error = {'exception' => e.class.name, 'message' => e.message}
              failure = true
            end
          end
        end
      end

      if failure
        execution_plan.status = 'paused'
      else
        execution_plan.status = 'finished'
      end
      return !failure
    end

    def run_execution_plan(execution_plan)
      failure = false
      execution_plan.actions.map do |action|
        next action if failure || %w[skipped finalize_skipped success].include?(action.status)
        action.persist_before_run
        begin
          action = self.process(action)
          action.status = 'success'
        rescue Exception => e
          action.run_error = {'exception' => e.class.name, 'message' => e.message}
          action.status = 'error'
          failure = true
        end
        action.persist_after_run
        action
      end
    end

    def transaction_driver
      nil
    end

    def in_transaction_if_possible
      if transaction_driver
        ret = nil
        transaction_driver.transaction do
          ret = yield
        end
        return ret
      else
        return yield
      end
    end

    def rollback_transaction
      transaction_driver.rollback if transaction_driver
    end


    def persistence_driver
      nil
    end

    def persist_plan_if_possible(action_class, execution_plan)
      if persistence_driver
        persistence_driver.persist(action_class, execution_plan)
      end
    end

    def process(action)
      # TODO: here goes the message validation
      if action.respond_to?(:run)
        # clear previous output records
        action.output = {}
        action.run
      end
      return action
    end

    # performs the planning phase of an action, but rollbacks any db
    # changes done in this phase. Returns the resulting execution
    # plan. Suitable for debugging.
    def preview_execution_plan(action_class, *args)
      unless transaction_driver
        raise "Bus doesn't know how to run in transaction"
      end

      execution_plan = nil
      transaction_driver.transaction do
        execution_plan = prepare_execution_plan(action_class, *args)
        transaction_driver.rollback
      end
      return execution_plan
    end

    def logger
      @logger ||= Dynflow::Logger.new(self.class)
    end

    class MemoryBus < Bus
      # No modifications needed: the default implementation is
      # in memory. TODO: get rid of this class
    end

    class ActiveRecordTransaction
      class << self

        def transaction(&block)
          ActiveRecord::Base.transaction(&block)
        end

        def rollback
          raise ActiveRecord::Rollback
        end

      end
    end

    # uses Rails API for db features
    # encapsulates the planning and finalization phase into
    class RailsBus < Bus

      def transaction_driver
        ActiveRecordTransaction
      end

      def persistence_driver
        Dynflow::Journal
      end

    end

  end
end
