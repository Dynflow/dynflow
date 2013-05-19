require 'test_helper'

module Dynflow

  describe "executor" do

    let(:execution_plan) do
      plan = ExecutionPlan.new
      plan.run_steps = run_steps
    end

    let(:run_steps) do
      []
    end

    before do
      Dummy.log_init
    end

    class Dummy < Action

      class << self
        attr_accessor :log

        def log_init
          self.log = []
        end
      end

      def run
        self.class.log << input['action']
        output['from'] = input['action']
      end

    end

    def run_step(name, input)
      Step::Run.new(Dummy.new(input.merge('action' => name.to_s)))
    end

    def output_ref(step)
      Step::Reference.new(step, 'output')
    end

    let(:build_image) do
      run_step(:build_image, 'name' => 'webserver', 'os' => 'rhel6')
    end

    let(:deploy_image) do
      run_step(:deploy_image,
               'location' => 'my-deploy-server', 'image' => output_ref(build_image))
    end

    let(:reserve_ip) do
      run_step(:reserve_ip, 'mac' => '52:54:00:10:4b:fd')
    end

    let(:set_dns) do
      run_step(:set_dns, 'name' => 'webserver', 'ip' => output_ref(reserve_ip))
    end

    let(:run_system) do
      run_step(:run_system,
               'image' => output_ref(deploy_image), 'dns' => output_ref(set_dns))
    end

    let(:run_plan) do
      ExecutionPlan::Sequence.new do |main_steps|
        main_steps << ExecutionPlan::Concurrence.new do |prepare_steps|
          prepare_steps << ExecutionPlan::Sequence.new do |build_steps|
            build_steps << build_image
            build_steps << deploy_image
          end
          prepare_steps << ExecutionPlan::Sequence.new do |net_steps|
            net_steps << reserve_ip
            net_steps << set_dns
          end
        end
        main_steps << run_system
      end
    end

    it 'runs all steps' do
      Executor.new.run(run_plan)
      Dummy.log.sort.must_equal %w[build_image deploy_image reserve_ip run_system set_dns]
    end

    it 'performs dereferention before runing the step' do
      Executor.new.run(run_plan)
      deploy_image.input['image'].must_equal('from' => 'build_image')
    end
  end

end
