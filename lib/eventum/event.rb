module Eventum
  class Event < Message
    attr_reader :_id, :_transaction_id

    def initialize(data, id = nil, transaction_id = nil)
      @subrequest_id_generator = 0
      @_id = id || [1]
      @_transaction_id = transaction_id || rand(1e10).to_s
      super(data)
    end


    # for purposes of using in log messages
    def to_s
      "#{self.class}: #{_transaction_id}-#{_id.join('-')}"
    end

    def self.decode(data)
      super
      @_transaction_id = data['transaction_id']
      @_id = data['id']
      @subrequest_id_generator = data['subrequest_id_generator']
    end

    def encode
      super.merge('id' => _id,
                  'transaction_id' => _transaction_id,
                  'subrequest_id_generator' => @subrequest_id_generator)
    end

    # the block contains the expression in Apipie::Params::DSL
    # describing the format of message
    def self.format(&block)
      if block
        # we don't evaluate the block right away, because there might
        # be unresolved constatns there
        @format_block = block
      else
        @format ||= Apipie::Params::Description.define(&@format_block)
      end
    end

    # so that it can be reused in other definition
    def self.descriptor
      self.format.descriptor
    end

    def validate!
      self.class.format.validate!(@data)
    end

    private

    def build_submessage(type, value)
      type.new(value, build_subrequest_id,  _transaction_id)
    end

    def build_subrequest_id
      @subrequest_id_generator += 1
      _id + [@subrequest_id_generator]
    end

  end
end
