module Eventum
  class OrchRequest < Message
    def self.response_class
      unless self.name =~ /::Request\Z/
        raise "Unexpected class name, #{self.name} expected to end with ::Request"
      end
      begin
        self.name.sub(/::Request\Z/, '::Response').constantize
      rescue NameError => e
        OrchResponse
      end
    end
  end
end
