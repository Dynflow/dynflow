# frozen_string_literal: true

require_relative 'test_helper'
require 'mocha/minitest'

module Dynflow
  describe 'flow' do
    class TestRegistry < Flows::Registry
      class << self
        def reset!
          @serialization_map = {}
        end
      end
    end

    after do
      TestRegistry.reset!
    end

    describe "registry" do
      it "allows registering values" do
        TestRegistry.register!(TestRegistry, 'TS')
        TestRegistry.register!(Integer, 'I')
        map = TestRegistry.instance_variable_get("@serialization_map")
        _(map).must_equal({ 'TS' => TestRegistry, 'I' => Integer })
      end

      it "prevents overwriting values" do
        TestRegistry.register!(Integer, 'I')
        _(-> { TestRegistry.register!(Float, 'I') }).must_raise Flows::Registry::IdentifierTaken
      end

      it "encodes and decodes values" do
        TestRegistry.register!(Integer, 'I')
        _(TestRegistry.encode(Integer)).must_equal 'I'
      end

      it "raises an exception when unknown key is requested" do
        _(-> { TestRegistry.encode(Float) }).must_raise Flows::Registry::UnknownIdentifier
        _(-> { TestRegistry.decode('F') }).must_raise Flows::Registry::UnknownIdentifier
      end
    end
  end
end
