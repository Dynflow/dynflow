module Dynflow
  module Action::FinalPhase
    def to_hash
      super.merge input:  input,
                  output: output,
                  error:  error
    end

    def execute
      with_error_handling do
        # ...
      end
    end
  end
end
