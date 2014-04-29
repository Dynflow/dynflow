require_relative 'test_helper'
module Dynflow
  module ExporterTest
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
          @exporter = Exporters::Hash.new(execution_plan)
        end

        let(:atom_keys) do
          %w(state action_class action_id error started_at ended_at
             execution_time real_time progress_done progress_weight).map(&:to_sym)
        end

        it 'exports execution plan items properly' do
          direct_keys = [:id, :state, :result, :started_at, :ended_at, :execution_time, :real_time]
          changed_keys = [:execution_history, :phase, :sub_plans, :delay_record]
          all_keys = direct_keys + changed_keys
          exported_plan = @exporter.export
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
          exported_plan = @exporter.export

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

          exported_plan = @exporter.export
          assert_correct_type.call(exported_plan[:phase][:run])
        end

        it 'exports finalize phase properly' do
          exported_plan = @exporter.export
          finalize = exported_plan[:phase][:finalize]
          finalize[:type].must_equal 'sequence'
          finalize[:steps].count.must_equal execution_plan.finalize_flow.flows.count
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

      let(:fake_console) { MiniTest::Mock.new }


      it 'renders one execution plan' do
        fake_console.expect(:erb, nil, [:export,
                                        :locals => {
                                          :template => :show,
                                          :plan => execution_plans.first
                                        }])
        exporter = ::Dynflow::Exporters::HTML.new(execution_plans.first, :console => fake_console)
        exporter.export
        assert fake_console.verify
      end

      it 'renders index' do
        fake_console.expect(:erb, nil, [:export,
                                        :locals => {
                                          :template => :index,
                                          :plans => execution_plans }])
        exporter = ::Dynflow::Exporters::HTML.new(execution_plans, :console => fake_console)
        exporter.export_index
        assert fake_console.verify
      end

      it 'renders all plans' do
        execution_plans.each do |plan|
          fake_console.expect(:erb, nil, [:export,
                                          :locals => {
                                            :template => :show,
                                            :plan => plan
                                          }])
        end
        exporter = ::Dynflow::Exporters::HTML.new(execution_plans, :console => fake_console)
        exporter.export_all_plans
        assert fake_console.verify
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

      let(:fake_tar) do
        tar = MiniTest::Mock.new
        tar.expect(:finalize, nil)
      end

      it 'does full html export' do
        exported_plans = Hash[execution_plans.map { |plan| [plan.id + '.html', 'html-' + plan.id]  }]
        fake_console = MiniTest::Mock.new

        fake_html = MiniTest::Mock.new
        fake_html.expect(:export_index, 'index')
        fake_html.expect(:export_all_plans, exported_plans.values)

        fake_tar.expect(:add_assets, fake_tar)
        fake_tar.expect(:add, fake_tar, [exported_plans.merge('index.html' => 'index')])

        ::Dynflow::Exporters::Tar.stub :new, fake_tar do
          ::Dynflow::Exporters::HTML.stub :new, fake_html, [execution_plans, :console => fake_console] do
            ::Dynflow::Exporters::Tar.full_html_export(execution_plans, fake_console)
          end
        end
        assert fake_tar.verify
        assert fake_html.verify
      end

      it 'does full JSON export' do
        exported_plans = Hash[execution_plans.map { |plan| [plan.id + '.json', '{}'] }]
        fake_tar.expect(:add, fake_tar, [exported_plans])
        ::Dynflow::Exporters::Tar.stub :new, fake_tar do
          ::Dynflow::Exporters::Hash.stub :export_execution_plan, {} do
            ::Dynflow::Exporters::Tar.full_json_export(execution_plans)
          end
        end
        assert fake_tar.verify
      end

    end
  end
end
