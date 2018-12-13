#!/usr/bin/env ruby
require_relative 'example_helper'

class SingletonExample < Dynflow::Action
  include Dynflow::Action::Singleton

  def run
    sleep 10
  end
end

class SingletonExampleA < SingletonExample; end
class SingletonExampleB < SingletonExample; end

if $0 == __FILE__
  ExampleHelper.world.action_logger.level = Logger::INFO
  ExampleHelper.world
  t1 = ExampleHelper.world.trigger(SingletonExampleA)
  t2 = ExampleHelper.world.trigger(SingletonExampleA)
  ExampleHelper.world.trigger(SingletonExampleA) unless SingletonExampleA.singleton_locked?(ExampleHelper.world)
  t3 = ExampleHelper.world.trigger(SingletonExampleB)
  db = ExampleHelper.world.persistence.adapter.db

  puts example_description
  puts <<-MSG.gsub(/^.*\|/, '')
    |  3 execution plans were triggered:
    |  #{t1.id} should finish successfully
    |  #{t3.id} should finish successfully because it is a singleton of different class
    |  #{t2.id} should fail because #{t1.id} holds the lock
    |
    |  You can see the details at
    |    http://localhost:4567/#{t1.id}
    |    http://localhost:4567/#{t2.id}
    |    http://localhost:4567/#{t3.id}
    |
  MSG
  ExampleHelper.run_web_console
end
