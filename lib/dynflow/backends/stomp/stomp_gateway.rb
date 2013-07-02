require 'stomp'

module Dynflow
  module Backends
    class StompGateway
  
      attr_reader :host, :port, :queue, :client

      @@plan_channel = "/queue/dynflow/plan"
      @@step_channel = "/queue/dynflow/step"
      @@result_channel = "/queue/dynflow/result"

      def initialize(args={})
        @host = args.fetch(:host, "localhost")
        @port = args.fetch(:port, 61613)
        @client = Stomp::Client.new({
          :hosts => [{:host => @host, :port => @port}]
        })
      end

      def publish_plan(plan_id)
        @client.publish(@@plan_channel, {
          :plan_id => plan_id
        }.to_json)
      end

      def subscribe_to_plan(&block)
        subscribe(@@plan_channel, block)
      end

      def publish_step(step_id)
        @client.publish(@@step_channel, {
          :step_id => step_id
        }.to_json)
      end

      def subscribe_to_step(&block)
        subscribe(@@step_channel, block)
      end

      def publish_result(step_id)
        @client.publish(@@result_channel, {
          :step_id => step_id
        }.to_json)
      end

      def subscribe_to_result(&block)
        subscribe(@@result_channel, block)
      end

      def subscribe(channel, block)
        @client.subscribe(channel) do |message|
          block.call(message)
        end
      end

    end
  end
end
