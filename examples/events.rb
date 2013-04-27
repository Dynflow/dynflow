# Shows how Dynflow can be used for events architecture: actions are
# subscribed to an event. When the event is triggered all the
# subscribed actions are preformed.

$:.unshift(File.expand_path('../../lib', __FILE__))

require 'dynflow'
require 'pp'

# this is an event that can be triggered.
# it has an input format so that the interface is given
# TODO: the validations are turned off right now
class Click < Dynflow::Action
  input_format do
    param :x, Integer
    param :y, Integer
  end
end

# SayHello subscibes to the event: it's run when the event is triggered
class SayHello < Dynflow::Action

  def self.subscribe
    Click
  end

  def run
    puts "Hello World"
  end
end

# we can subscribe more actions to an event
class SayPosition < Dynflow::Action

  def self.subscribe
    Click
  end

  def run
    puts "your position is [#{input['x']} - #{input['y']}]"
  end

end

# we can even subscribe to an action that is subscribed to an event
class SayGoodbye < Dynflow::Action

  def self.subscribe
    SayPosition
  end

  def run
    puts "Good Bye"
  end
end

Click.trigger('x' => 5, 'y' => 4)
# gives us:
# Hello World
# your position is [5 - 4]
# Good Bye

pp Click.plan('x' => 5, 'y' => 4).actions
# returns the execution plan for the event (nothing is triggered):
# [
# since the event is action as well, it could have a run method
# [Click:       {"x"=>5, "y"=>4} ~> {},
#  SayHello:    {"x"=>5, "y"=>4} ~> {},
#  SayPosition: {"x"=>5, "y"=>4} ~> {},
#  SayGoodbye:  {"x"=>5, "y"=>4} ~> {}]
# ]
