# Shows how Dynflow can be used for dynamic workflow definition
# and execution.
# In a planning phase of an action, a sub-action can be planned as
# well.


$:.unshift(File.expand_path('../../lib', __FILE__))

require 'dynflow'
require 'pp'

class Article < Struct.new(:title, :body, :color); end

class Publish < Dynflow::Action
  input_format do
    param :title, Integer
    param :body, Integer
  end

  # plan can take arbitrary arguments. The args are passed from the
  # trigger method.
  def plan(article)
    # we can explicitly plan a subaction
    plan_self 'title' => article.title, 'body' => article.body
    plan_action Review, article
  end

  def run
    puts 'Starting'
  end

  # after all actions are run, there is a finishing phase. All the
  # actions with +finished+ action defined are called, passing all the
  # performed actions (with inputs and outputs)
  def finalize(outputs)
    printer_action = outputs.find { |o| o.is_a? Print }
    puts "Printer says '#{printer_action.output['message']}'"
  end
end

class Review < Dynflow::Action

  # the actions can provide an output for the finalizing phase
  output_format do
    param :rating, Integer
  end

  # the plan method takes the same arguments as the parent action
  def plan(article)
    # in the input attribute the input for the parent action is
    # available
    plan_self input
  end

  # if no plan method given, the input is the same as the action that
  # triggered it
  def run
    puts "Reviewing #{input['title']}"
    raise "Too Short" if input['body'].size < 6
    output['rating'] = input['body'].size
  end

  def finalize(outputs)
    # +input+ and +output+ attributes are available in the finalizing
    # phase as well.
    puts "The rating was #{output['rating']}"
  end

end

class Print < Dynflow::Action

  input_format do
    param :title, Integer
    param :body, Integer
    param :color, :boolean
  end

  output_format do
    param :message, String
  end

  # if needed, we can subscribe to an action instead of explicitly
  # specifying it in the plan method. Suitable for plugin architecture.
  def self.subscribe
    Review # sucessful review means we can print
  end

  def plan(article)
    plan_self input.merge('color' => article.color)
  end

  def run
    if input['color']
      puts "Printing in color"
    else
      puts "Printing blank&white"
    end
    output['message'] = "Here you are"
  end
end

short_article = Article.new('Short', 'Short', false)
long_article = Article.new('Long', 'This is long', false)
colorful_article = Article.new('Long Color', 'This is long in color', true)

pp Publish.plan(short_article)
# the expanded workflow is:
# [
#  [Publish, {"title"=>"Short", "body"=>"Short"}],
#  [Review, {"title"=>"Short", "body"=>"Short"}],
#  [Print, {"title"=>"Short", "body"=>"Short", "color"=>false}]
# ]

begin
  Publish.trigger(short_article)
rescue => e
  puts e.message
end
# Produces:
# Starting
# Reviewing Short
# Too Short

Publish.trigger(long_article)
# Produces:
# Starting
# Reviewing Long
# Printing blank&white
# Printer says 'Here you are'
# The rating was 12


Publish.trigger(colorful_article)
# Produces:
# Starting
# Reviewing Long Color
# Printing in color
# Printer says 'Here you are'
# The rating was 21
