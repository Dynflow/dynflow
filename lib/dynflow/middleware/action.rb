module Dynflow
  module Middleware::Action

    def middleware
      @middleware ||= Middleware::Register.new
    end

  end
end
