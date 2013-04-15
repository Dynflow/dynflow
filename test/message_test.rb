require 'test_helper'
require 'json'
require 'forwardable'

describe Eventum::Message do

  # TODO: this belongs to event_test
  class AddressMessage < Eventum::Event

    format do
      param :street, String
      param :zip,    String
    end

  end

  class TestMessage < Eventum::Event

    format do
      param :name,    String
      param :age,     Integer
      param :address, AddressMessage
    end

  end

  before do
    @test_data = {
      :name => 'Peter Smith',
      :age => 38,
      :address => { :street => "Baker's street'", :zip => '007' }
    }

    @test_message = TestMessage.new(@test_data)
  end

  describe '[]' do

    it 'delegates to a data hash with indifferent access' do
      @test_message['name'].must_equal 'Peter Smith'
      @test_message[:address]['zip'].must_equal '007'
    end

  end

  describe 'serialization' do

    describe 'encode' do

      it 'tranfers the data into serializable hash' do
        encoded_data = @test_message.encode
        json_transferred_data = JSON.load(JSON.dump(encoded_data))
        json_transferred_data.must_equal encoded_data
      end

    end

    describe 'decode' do

      it 'reconstructs the original object from its hash representation' do
        decoded_message = Eventum::Message.decode(@test_message.encode)
        decoded_message.class == @test_message.class
        decoded_message[:name].must_equal @test_message[:name]
        decoded_message[:address][:zip].must_equal @test_message[:address][:zip]
      end

    end

  end

  describe 'validation' do

    it 'succeeds on valid data' do
      @test_message.validate!
    end

    it 'fails on invalid data' do
      @test_message[:address][:zip] = 123
      lambda { @test_message.validate! }.must_raise Apipie::Params::Errors::Invalid
    end

  end

end
