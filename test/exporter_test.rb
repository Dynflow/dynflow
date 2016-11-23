require_relative 'test_helper'
require 'ostruct'

module Dynflow
  module ExporterTest

    describe ::Dynflow::Exporters::Abstract do
      let(:fake_world) { MiniTest::Mock.new }
      let(:exporter) { ::Dynflow::Exporters::Abstract.new(fake_world) }
      let(:plan) { OpenStruct.new(:id => 1) }
      let(:plan2) { OpenStruct.new(:id => 2) }
      let(:index) { { plan.id => { :plan => plan, :result => nil } } }

      it '#add' do
        ret = exporter.add(plan)
        assert_equal exporter.index, index
        assert_equal ret, exporter
      end

      it '#add_id' do
        ret = exporter.add_id(plan.id)
        expected = { plan.id => { :plan => nil, :result => nil } }
        assert_equal exporter.index, expected
        assert_equal ret, exporter
      end

      it '#add_many' do
        ret = exporter.add_many([plan, plan2])
        expected = { plan.id => { :plan => plan, :result => nil},
                     plan2.id => { :plan => plan2, :result => nil} }
        assert_equal exporter.index, expected
        assert_equal ret, exporter
      end

      it '#add_many_ids' do
        expected = { plan.id => { :plan => nil, :result => nil},
                     plan2.id => { :plan => nil, :result => nil} }

        ret = exporter.add_many_ids([plan.id, plan2.id])
        assert_equal exporter.index, expected
        assert_equal ret, exporter
      end

      it '#finalize, #result' do
        msg = 'stubbed'
        expected = { plan.id => { :plan => plan, :result => msg } }
        exporter.stub(:export, proc { |_thing| msg }) do
          exporter.add(plan).finalize
        end

        assert exporter.index.frozen?
        exporter.index.each { |_, value| assert value.frozen? }
        assert_equal exporter.index, expected

        assert_equal exporter.result, [msg]
      end

      it '#resolve_ids' do
        fake_persistence = MiniTest::Mock.new
        fake_world.expect(:persistence, fake_persistence)
        fake_persistence.expect(:find_execution_plans, [plan], [:filters => { :uuid => [plan.id] }])

        exporter.add_id(plan.id)
        exporter.send(:resolve_ids)
        assert_equal exporter.index, index
      end
    end

    describe ::Dynflow::Exporters::Hash do

      before do
        @world = WorldFactory.create_world
      end

      let :execution_plan do
        @world.plan(Support::CodeWorkflowExample::FastCommit, 'sha' => 'abc123')
      end

      let :ref_action do
        @world.persistence.load_action(execution_plan.steps[3])
      end

      describe 'execution plan export' do

        before do
          execution_plan.save
          @exporter = Exporters::Hash.new(@world)
          @exporter.add(execution_plan)
        end

        let(:atom_keys) do
          %w(state action_class action_id error started_at ended_at
             execution_time real_time progress_done progress_weight).map(&:to_sym)
        end

        it 'exports execution plan items properly' do
          direct_keys = [:id, :state, :result, :started_at, :ended_at, :execution_time, :real_time]
          changed_keys = [:execution_history, :phase, :sub_plans, :delay_record]
          all_keys = direct_keys + changed_keys
          exported_plan = @exporter.send(:export, execution_plan)
          execution_plan_hash = execution_plan.to_hash
          assert exported_plan.keys.all? { |key| all_keys.include? key }
          direct_keys.each do |key|
            exported_plan[key].must_equal execution_plan_hash[key]
          end
          exported_plan[:execution_history].each do |history|
            history[:time].must_be Time
          end
          exported_plan[:sub_plans].must_be_empty
          exported_plan[:delay_record].must_be_empty
        end

        it 'exports plan phase properly' do
          exported_plan = @exporter.send(:export, execution_plan)

          action = ->(flow) do
            execution_plan.actions[flow[:action_id] - 1]
          end

          assert_correct_plan_phase = ->(flow) do
            assert_equal atom_keys.count, flow.keys.count - 3
            a = action.call(flow)
            assert_equal a.to_hash[:input], flow[:input]
            assert_equal a.to_hash[:output], flow[:output]
            plan_step = a.plan_step
            plan_step.to_hash.reject { |key, _| !atom_keys.include? key }.all? do |key, value|
              assert_equal value, flow[key]
            end
            flow[:children].all? { |child| assert_correct_plan_phase.call(child) }
          end

          assert_correct_plan_phase.call(exported_plan[:phase][:plan])
          batch_exported = @exporter.finalize.index[execution_plan.id][:result]
          assert_correct_plan_phase.call(batch_exported[:phase][:plan])
        end

        it 'exports run phase properly' do
          flow_step = ->(flow) do
            execution_plan.actions[flow[:step][:action_id] - 1].run_step
          end

          assert_correct_type = ->(flow) do
            if %w(sequence concurrence).include?(flow[:type])
              assert(flow[:steps].all? { |flow| assert_correct_type.call(flow) })
            elsif flow[:type] == 'atom'
              assert_equal atom_keys.count, flow[:step].keys.count
              step = flow_step.call(flow).to_hash
              step.select { |key, _| atom_keys.include? key }.all? do |key, value|
                assert_equal value, flow[:step][key]
              end
            else
              # Flow type has to be atom, concurrence or sequence
              assert false
            end
          end

          exported_plan = @exporter.send(:export, execution_plan)
          assert_correct_type.call(exported_plan[:phase][:run])
          batch_exported = @exporter.finalize.index[execution_plan.id][:result]
          assert_correct_type.call(batch_exported[:phase][:run])
        end

        it 'exports finalize phase properly' do
          exported_plan = @exporter.send(:export, execution_plan)
          batch_exported = @exporter.finalize.index[execution_plan.id][:result]

          finalize = exported_plan[:phase][:finalize]
          finalize[:type].must_equal 'sequence'
          finalize[:steps].count.must_equal execution_plan.finalize_flow.flows.count
          assert_equal finalize, batch_exported[:phase][:finalize]
        end

      end
    end

    describe ::Dynflow::Exporters::HTML do
      before do
        @world = WorldFactory.create_world
        execution_plans.each(&:save)
      end

      let(:execution_plans) do
        2.times.map { @world.plan(Support::CodeWorkflowExample::FastCommit, 'sha' => 'abc123') }
      end

      let(:fake_renderer) { MiniTest::Mock.new }
      let(:exporter) { ::Dynflow::Exporters::HTML.new(@world) }

      it 'renders one execution plan' do
        fake_renderer.expect(:render, nil, [:export,
                                            :locals => {
                                              :template => :show,
                                              :plan => execution_plans.first
                                            }])
        ::Dynflow::Exporters::TaskRenderer.stub(:new, fake_renderer) do
          exporter.add(execution_plans.first).finalize
          assert fake_renderer.verify
        end
      end

      it 'renders index' do
        fake_renderer.expect(:render, nil, [:export,
                                            :locals => {
                                              :template => :index,
                                              :plans => execution_plans }])
        ::Dynflow::Exporters::TaskRenderer.stub(:new, fake_renderer) do
          exporter.add_many(execution_plans).export_index
          assert fake_renderer.verify
        end
      end

      it 'renders all plans' do
        execution_plans.each do |plan|
          fake_renderer.expect(:render, nil, [:export,
                                              :locals => {
                                                :template => :show,
                                                :plan => plan
                                              }])
        end
        ::Dynflow::Exporters::TaskRenderer.stub(:new, fake_renderer) do
          exporter.add_many(execution_plans).finalize
          assert fake_renderer.verify
        end
      end
    end

    describe ::Dynflow::Exporters::CSV do

      before do
        @world = WorldFactory.create_world
        execution_plans.each(&:save)
      end

      let(:exporter) { exporter = ::Dynflow::Exporters::CSV.new(@world) }
      let(:header) do
        ::Dynflow::Exporters::CSV::WANTED_ATTRIBUTES.map(&:to_s).join(',')
      end
      let(:execution_plans) do
        2.times.map { @world.plan(Support::CodeWorkflowExample::FastCommit, 'sha' => 'abc123') }
      end

      it 'renders header' do
        assert_equal exporter.result, header
      end

      it 'renders plans' do
        exporter.add_many(execution_plans)
        lines = exporter.result.split("\n")
        assert_equal lines.first, header
        execution_plans.each_with_index do |plan, index|
          data = Hash[::Dynflow::Exporters::CSV::WANTED_ATTRIBUTES.zip(lines[index + 1].split(','))]
          assert_equal data[:id], plan.id
          assert_equal data[:state], plan.state.to_s
          assert_equal data[:result], plan.result.to_s
          assert_equal data[:parent_task_id], plan.caller_execution_plan_id.to_s
          assert_equal data[:label], plan.entry_action.class.name
        end
      end
    end

    describe ::Dynflow::Exporters::Tar do

      before do
        @world = WorldFactory.create_world
        execution_plans.each(&:save)
      end

      let(:execution_plans) do
        2.times.map { @world.plan(Support::CodeWorkflowExample::FastCommit, 'sha' => 'abc123') }
      end

      it 'wraps another exporter' do
        dummy = MiniTest::Mock.new
        dummy.expect(:add, dummy, [1])
        dummy.expect(:add_id, dummy, [2])
        dummy.expect(:finalize, dummy)
        dummy.expect(:index, [])

        exporter = ::Dynflow::Exporters::Tar.new(dummy)
        exporter.add(1).add_id(2).finalize
        assert dummy.verify
      end

      it 'writes to any IO object' do
        fake_io = MiniTest::Mock.new
        fake_io.expect(:close, nil)
        # Expects write three times, we don't care about arguments
        3.times { fake_io.expect(:write, nil) { true } }

        dummy = MiniTest::Mock.new
        dummy.expect(:finalize, nil)
        dummy.expect(:index, { '1' => { :result => 'foo' } })

        exporter = ::Dynflow::Exporters::Tar.new(dummy, :io => fake_io, :filetype => '')
        exporter.finalize

        assert fake_io.verify
        assert dummy.verify
      end
    end

  end
end
