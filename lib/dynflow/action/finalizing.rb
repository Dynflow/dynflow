module Dynflow
  module Action::Finalizing
    def to_hash
      super.merge input:  input,
                  output: output,
                  error:  error
    end
  end
end
