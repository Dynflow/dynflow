module Dynflow
  class Serializable
    def self.new_from_hash(*args, hash)
      raise NotImplementedError
      # new ...
    end

    def to_hash
      raise NotImplementedError
    end
  end
end
