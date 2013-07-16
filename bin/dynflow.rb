#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'eventmachine'

$:.unshift(File.expand_path('../../lib', __FILE__))
require 'dynflow'
require '../katello/config/environment'
require './bin/step_consumer'
require File.expand_path('../../examples/workflow', __FILE__)


module Dynflow
  class ProcessManager

    attr_reader :gateway

    def initialize
      @gateway = Dynflow::Backends::StompGateway.new
      @executor = Dynflow::Executors::AsyncExecutor.new({:gateway => @gateway})
      @manager = Dynflow::Manager.new({
        :persistence_driver => Dynflow::Persistence::ActiveRecordDriver.new,
        :serialization_driver => Dynflow::Serialization::SimpleSerializationDriver.new
      })
    end

    def run
      EM.run do
        puts "Subscribed and listening"

        @gateway.subscribe_to_plan do |message|
          process_plan(message)
        end

        @gateway.subscribe_to_result do |message|
          process_result(message)
        end

        consumer = Dynflow::StepConsumer.new.run
      end
    end

    def process_plan(message)
      data = MultiJson.load(message.body)

      puts "Loading the plan up"
      plan = @manager.load_execution_plan(data['plan_id'])
      puts plan
      puts plan.run_plan
      step = @executor.execute(plan.run_plan)

      if step
        @gateway.publish_step(step.persistence_id)
      else
        puts "Jobs Done"
      end
    rescue => e
      puts e
      puts e.backtrace
    end

    def process_result(message)
      data = MultiJson.load(message.body)

      puts "Received a step result"
      step = @manager.load_step(data['step_id'])

      @gateway.publish_plan(step.persisted_plan_id)
    rescue => e
      puts e
      puts e.backtrace
    end
  
  end
end

process_manager = Dynflow::ProcessManager.new
process_manager.run
