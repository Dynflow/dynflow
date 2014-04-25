require_relative 'test_helper'
require 'pry'
module Dynflow
  module ExportImportTest
    describe 'export-import' do

      before do 
        @world = Dynflow::SimpleWorld.new
        @exporter = Dynflow::Exporter.new @world
      end

      let :execution_plan do
        @world.plan(Support::CodeWorkflowExample::FastCommit, 'sha' => 'abc123')
      end

      let :path do
        "testlogs"
      end

      let :ref_action do
        @world.persistence.load_action(execution_plan.steps[3]) 
      end

      describe 'execution plan export' do

        before do
          execution_plan.save
          @exporter.export_execution_plan(execution_plan.id)
          @exporter.export_to_dir(path)
          @exporter.export_execution_plan(execution_plan.id)
        end

        it 'creates a structure like path/execution_plan_id/plan.json' do
          Dir.exists?(path).must_equal true
          Dir.exists?("#{path}/#{execution_plan.id}").must_equal true
          File.exists?("#{path}/#{execution_plan.id}/plan.json").must_equal true
        end

        it 'makes hash from db properly' do
          execution_plan_hash = execution_plan.to_hash
          execution_plan_hash[:id].must_equal @exporter.execution_plan[:id]
          execution_plan_hash[:class].must_equal @exporter.execution_plan[:class]
          execution_plan_hash[:state].must_equal @exporter.execution_plan[:state]
          execution_plan_hash[:started_at].must_equal @exporter.execution_plan[:started_at]
          execution_plan_hash[:ended_at].must_equal @exporter.execution_plan[:ended_at]
          execution_plan_hash[:execution_time].must_equal @exporter.execution_plan[:execution_time]
          execution_plan_hash[:real_time].must_equal @exporter.execution_plan[:real_time]
        end

        it 'plan.json contents equals json generated from execution plan' do
          File.open("#{path}/#{execution_plan.id}/plan.json",'r') do |f|
            f.read.must_equal JSON.generate(@exporter.execution_plan)
            f.close
          end
        end

        after do
          File.exists?("#{path}/#{execution_plan.id}/plan.json") && File.delete("#{path}/#{execution_plan.id}/plan.json")
          Dir.exists?("#{path}/#{execution_plan.id}") && Dir.delete("#{path}/#{execution_plan.id}")
          Dir.exists?(path) && Dir.delete(path)
        end

      end

      describe 'action export' do

        before do
          @exporter.export_action(execution_plan.id, ref_action.id)
          @exporter.export_to_dir(path)
        end

        it 'adds exported actions to array' do
          count = @exporter.actions.count
          @exporter.export_action(execution_plan.id, ref_action.id)
          @exporter.actions.count.must_equal count+1
        end

        it 'exports to path/execution_plan_id/action-action_id.json' do
          Dir.exists?(path).must_equal true
          Dir.exists?("#{path}/#{execution_plan.id}").must_equal true
          File.exists?("#{path}/#{execution_plan.id}/action-#{ref_action.id}.json").must_equal true
        end

        it 'makes action-#{ref_action.id}.json contents equal json generated from ref action' do
          @exporter.export_action(execution_plan.id, ref_action.id)
          File.open("#{path}/#{execution_plan.id}/action-#{ref_action.id}.json",'r') do |f|
            f.read.must_equal JSON.generate(@exporter.actions.first.to_hash)
            f.close
          end
        end

        after do
          Dir.glob("#{path}/#{execution_plan.id}/*.json").each { |f| File.delete(f) }
          Dir.exists?("#{path}/#{execution_plan.id}") && Dir.delete("#{path}/#{execution_plan.id}")
          Dir.exists?(path) && Dir.delete(path)
        end

      end

      describe 'plan import' do
        include PlanAssertions

        before do
          execution_plan.save
          execution_plan.steps.each_value { |step| @exporter.export_action(execution_plan.id, step.action_id) }
          @exporter.export_execution_plan(execution_plan.id)
          @exporter.export_to_dir(path)
          @dest_world = Dynflow::SimpleWorld.new
          @importer = Dynflow::Importer.new @dest_world
        end

        it 'raises ActionMissing when action file is missing' do
          File.delete("#{path}/#{execution_plan.id}/action-1.json")
          proc { @importer.import_from_dir("#{path}/#{execution_plan.id}/") }.must_raise ActionMissing
        end

        it 'should not fail' do
          File.open("#{path}/#{execution_plan.id}/action-42.json",'w') do |outputFile|
            File.open("#{path}/#{execution_plan.id}/action-1.json") do |inputFile|
              outputFile.write inputFile.read
              inputFile.close
            end
            outputFile.close
          end
          @importer.import_from_dir("#{path}/#{execution_plan.id}").must_be_instance_of Hash

        end

        it 'imports the plan properly' do
          @importer.import_from_dir("#{path}/#{execution_plan.id}/")
          dest_execution_plan = @dest_world.persistence.load_execution_plan(execution_plan.id)
          dest_execution_plan.id.must_equal execution_plan.id

          assert_steps_equal execution_plan.root_plan_step, dest_execution_plan.root_plan_step
          assert_equal execution_plan.steps.keys, dest_execution_plan.steps.keys

          dest_execution_plan.steps.each do |id, step|
            assert_steps_equal(step, execution_plan.steps[id])
          end
        end

        after do
          Dir.glob("#{path}/#{execution_plan.id}/*.json").each { |f| File.delete(f) }
          Dir.exists?("#{path}/#{execution_plan.id}") && Dir.delete("#{path}/#{execution_plan.id}")
          Dir.exists?(path) && Dir.delete(path)
        end
      end
    end
  end
end
