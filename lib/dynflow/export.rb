# frozen_string_literal: true

module Dynflow
  class Export
    attr_reader :world

    def initialize(world)
      @world = world
      @worlds = load_worlds
    end

    def prepare_execution_plan(plan)
      {
        uuid:              plan.id,
        label:             plan.label,
        state:             plan.state,
        result:            plan.result,
        started_at:        format_time(plan.started_at),
        ended_at:          format_time(plan.ended_at),
        execution_time:    plan.execution_time,
        real_time:         plan.real_time,
        execution_history: prepare_execution_history(plan.execution_history),
        plan_phase:        prepare_step(plan, plan.root_plan_step, :plan),
        run_phase:         prepare_flow(plan, plan.run_flow, :run),
        finalize_phase:    prepare_flow(plan, plan.finalize_flow, :finalize),
        delay_record:      plan.delay_record && plan.delay_record.to_hash
      }
    end

    private

    def prepare_step(execution_plan, step, phase)
      raise "Unexpected phase '#{phase}'" unless [:plan, :run, :finalize].include?(phase)
      action = execution_plan.actions.find { |a| a.public_send(:"#{phase}_step_id") == step.id }
      base = {
        id:             step.id,
        state:          step.state,
        queue:          step.queue,
        started_at:     format_time(step.started_at),
        ended_at:       format_time(step.ended_at),
        real_time:      step.real_time,
        execution_time: step.execution_time,
        label:          action.label,
        input:          action.input.to_hash,
        output:         action.output.to_hash
      }
      if phase == :plan
        base[:children] = step.children.map do |step_id|
          step = execution_plan.steps[step_id]
          prepare_step(execution_plan, step, phase)
        end
      end
      base
    end

    def prepare_execution_history(history)
      history.map do |entry|
        {
          event: entry.name,
          time: format_time(Time.at(entry.time)),
          world: {
            uuid: entry.world_id,
            meta: @worlds[entry.world_id]&.meta
          }
        }
      end
    end

    def prepare_delay_record(record)
      {
        start_at: format_time(record.start_at),
        start_before: format_time(record.start_before),
        frozen: record.frozen
      }
    end

    def world_meta(world_id)
      {
        uuid: world_id,
        meta: @world.fetch(world_id, {})
      }
    end

    def load_worlds
      world.coordinator.find_worlds(false).reduce({}) do |acc, cur|
        acc.merge(cur.id => cur)
      end
    end

    def prepare_flow(execution_plan, flow, phase)
      case flow
      when Dynflow::Flows::Sequence
        { type: 'sequence', children: flow.flows.map { |flow| prepare_flow(execution_plan, flow, phase) } }
      when Dynflow::Flows::Concurrence
        { type: 'concurrence', children: flow.flows.map { |flow| prepare_flow(execution_plan, flow, phase) } }
      when Dynflow::Flows::Atom
        step = execution_plan.steps[flow.step_id]
        prepare_step(execution_plan, step, phase)
      end
    end

    def format_time(time)
      # ISO8601
      return unless time
      time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    end
  end
end
