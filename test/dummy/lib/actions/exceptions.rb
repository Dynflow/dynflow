module Actions
  module Exceptions

    class PlanException < StandardError
    end

    class RunException < StandardError
    end

    class FinalizeException < StandardError
    end

  end
end
