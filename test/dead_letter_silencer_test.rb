# frozen_string_literal: true
require_relative 'test_helper'
require 'ostruct'

module Dynflow
  module DeadLetterSilencerTest
    describe ::Dynflow::DeadLetterSilencer do
      include Dynflow::Testing::Factories
      include TestHelpers

      let(:world) { WorldFactory.create_world }

      it 'is started for each world' do
        world.dead_letter_handler.actor_class
             .must_equal ::Dynflow::DeadLetterSilencer
      end

      describe ::Dynflow::DeadLetterSilencer::Matcher do
        let(:any) { DeadLetterSilencer::Matcher::Any }
        let(:sender) { ::Dynflow::Clock }
        let(:msg) { :ping }
        let(:receiver) { ::Dynflow::DeadLetterSilencer }
        let(:letter) do
          OpenStruct.new(:sender => OpenStruct.new(:actor_class => sender),
                         :message => msg,
                         :address => OpenStruct.new(:actor_class => receiver))
        end

        it 'matches any' do
          DeadLetterSilencer::Matcher.new(any, any, any).match?(letter).must_equal true
        end

        it 'matches comparing for equality' do
          DeadLetterSilencer::Matcher.new(sender, msg, receiver)
                                     .match?(letter).must_equal true
          DeadLetterSilencer::Matcher.new(any, :bad, any).match?(letter).must_equal false
        end

        it 'matches by calling the proc' do
          condition = proc { |actor_class| actor_class.is_a? Class }
          DeadLetterSilencer::Matcher.new(condition, any, condition)
                                     .match?(letter).must_equal true
        end
      end
    end
  end
end
