
module Dynflow
  module Initiators
    class StompInitiator
  
      attr_reader :gateway

      def initialize(args={})
        @gateway = Dynflow::Backends::StompGateway.new(args)
      end

      def start(plan)
        @gateway.publish_plan(plan.persistence_id)
      end

    end
  end
end
