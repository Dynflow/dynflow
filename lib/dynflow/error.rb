module Dynflow
  class Error < StandardError
    def to_hash
      { class: self.class.name, message: message, backtrace: backtrace }
    end

    def self.from_hash(hash)
      self.new(hash[:message]).tap { |e| e.set_backtrace(hash[:backtrace]) }
    end
  end
end
