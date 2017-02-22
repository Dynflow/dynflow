module Dynflow
  module Exporters

    class Hash < Abstract

      attr_reader :execution_plan, :world

      ACTION_KEYS = %w(input output).map(&:to_sym)
      STEP_FILTER = %w(execution_plan_id id class).map(&:to_sym)
      DELAYED_FILTER = %w(execution_plan_uuid args_serializer).map(&:to_sym)
      EXECUTION_PLAN_FILTER = %w(step_ids root_plan_step_id finalize_flow run_flow class).map(&:to_sym)

      def export(plan)
        @execution_plan = plan
        result = export_private
        @execution_plan = nil
        result
      end

      private

      def export_private
        hash = execution_plan.to_hash.delete_if { |key, _| EXECUTION_PLAN_FILTER.include? key }
        hash[:phase] = {
          :plan => export_planned_step(execution_plan.root_plan_step),
          :run => process_flow(execution_plan.run_flow),
          :finalize => process_flow(execution_plan.finalize_flow)
        }
        hash[:execution_history] = export_history
        hash[:sub_plans] = export_sub_plans
        hash[:delay_record] = export_delay_record
        hash
      end

      def export_history
        execution_plan.execution_history.to_hash.map do |history|
          history[:time] = Time.at(history[:time])
          history
        end
      end

      def process_flow(flow)
        case flow
        when ::Dynflow::Flows::Sequence
          { :type => 'sequence', :steps => flow.flows.map { |f| process_flow(f) } }
        when ::Dynflow::Flows::Concurrence
          { :type => 'concurrence', :steps => flow.flows.map { |f| process_flow(f) } }
        when ::Dynflow::Flows::Atom
          { :type => 'atom', :step => process_atom(flow.step_id) }
        else
          raise 'Unknown flow type'
        end
      end

      def process_atom(step_id)
        step = execution_plan.steps[step_id]
        hash = execution_plan.steps[step_id].to_hash.reject { |key, _| STEP_FILTER.include? key }
        hash[:action_class] = step.action_class.name
        hash
      end

      def export_planned_step(step)
        hash = step.to_hash.delete_if { |key, _| STEP_FILTER.include? key }
        hash[:input], hash[:output] = step.action(execution_plan).to_hash.values_at(*ACTION_KEYS)
        hash[:children] = step.planned_steps(execution_plan).map { |child| export_planned_step(child) }
        hash[:action_class] = step.action_class.name
        hash
      end

      def export_sub_plans
        sub_plans = execution_plan.sub_plans
                      .reject { |plan| plan.id == execution_plan.id }
        if !full? || sub_plans.empty?
          sub_plans.map(&:id)
        else
          exporter = Hash.new(:with_full_sub_plans => true)
          sub_plans.map { |sub_plan| exporter.export(sub_plan) }
        end
      end

      def export_delay_record
        if execution_plan.state == :scheduled
          if execution_plan.delay_record.nil?
            execution_plan.world.logger.error("No delay record found for scheduled plan #{execution_plan.id}")
            return {}
          end
          execution_plan.delay_record.to_hash.delete_if { |key, _| DELAYED_FILTER.include? key }
        else
          {}
        end
      end

      def full?
        @options.fetch(:with_full_sub_plans, true)
      end
    end

    class JSON < ::Dynflow::Exporters::Hash

      def export(plan)
        super(plan).to_json
      end

      def filetype
        'json'
      end

      def brackets
        ['[', ',', ']']
      end

    end
  end
end
