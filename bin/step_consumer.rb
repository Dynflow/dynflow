#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'eventmachine'

$:.unshift(File.expand_path('../../lib', __FILE__))
require 'dynflow'
require '../katello/config/environment'


module Dynflow
  class StepConsumer

    attr_reader :gateway, :worker

    def initialize
      @worker  = Dynflow::Worker.new
      @gateway = Dynflow::Backends::StompGateway.new
      @manager = Dynflow::Manager.new({
        :persistence_driver => Dynflow::Persistence::ActiveRecordDriver.new,
        :serialization_driver => Dynflow::Serialization::SimpleSerializationDriver.new
      })
    end

    def run
      EM.run do
        puts "Subscribed and listening for steps to execute"
        @gateway.subscribe_to_step do |message|
          process_step(message)
        end
      end
    end

    def process_step(message)
      puts "Received a step"

      data = MultiJson.load(message.body)
      step = @manager.load_step(data['step_id'])

      step = @worker.run(step)

      puts "Publishing result"
      @gateway.publish_result(step.persistence_id)
    rescue => e
      puts e
      puts e.backtrace
    end
  
  end
end
