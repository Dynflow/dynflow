---
layout: page
title: Documentation
countheads: true
toc: true
comments: true
---

{% danger_block %}

Work in progress! It contains a lot of typos, please let us know at the bottom in the comments 
or submit a PR against [pages branch](https://github.com/dynflow/dynflow/tree/pages). Thanks!

{% enddanger_block %}

## High level overview TODO

*TODO to be refined*

Dynflow (**DYN**amic work**FLOW**) is a workflow engine
written in Ruby that allows to:

-   Keep track of the progress of running processes
-   Run the code asynchronously
-   Resume the process when something goes wrong, skip some steps when needed
-   Detect independent parts and run them concurrently
-   Compose simple actions into more complex scenarios
-   Extend the workflows from third-party libraries
-   Keep consistency between local transactional database and
    external services
-   Suspend the long-running steps, not blocking the thread pool
-   Cancel steps when possible
-   Extend the actions behavior with middlewares
-   Pick different adapters to provide: storage backend, transactions, or executor implementation

Dynflow has been developed to be able to support orchestration of services in the
[Katello](http://katello.org) and [Foreman](http://theforeman.org/) projects.

*TODO*

-   what problems does Dynflow solve?
-   maybe a little history

## Glossary TODO

*TODO to be refined*

-   **Action** - building block of execution plans, a Ruby class inherited
    from `Dynflow::Action`, defines code to be run in each phase. 
-   **Phase** - Each action has three phases: `plan`, `run`, `finalize`.
-   **Input/Output** - Each action has one. It's a `Hash` of data which is persisted.
-   **Execution plan** - definition of the workflow: product of the plan phase
-   **Triggering an action** - entering the plan phase, starting with the plan
    method of the action. The execution follows immediately.
-   **Flow** - definition of the run/finalize phase, holding the information
    about steps that can run concurrently/in sequence. Part of execution plan.
-   **Executor** - service that executes the run and finalize flows based on
    the execution plan. It can run in the same process as the plan phase or in
    different process (using the remote executor)
-   **World** - the universe where the Dynflow runs the code: it holds all
    needed configuration.

##  Examples TODO

*TODO*

-   for async operations
-   for orchestrating system/ssh calls
-   for keeping consistency between local database and external systems
-   sub-tasks

## How to use

### World creation TODO

-   *include executor definition*

### Development vs production TODO

### Action anatomy

Each action can be viewed as a function. It's planned for execution with 
input, then it's executed producing output quite possibly having side-effects. 
After that some finalizing steps can be taken. Actions can use outputs of other actions
as parts of their inputs establishing dependency. Action's state is serialized between each phase
and survives machine/executor restarts.

As lightly touched in the previous paragraph there are 3 phases: planning, running, finalizing.
Planning phase starts by triggering an action.

#### Input and Output

Both input and output are `Hash`es accessible by `Action#input` and `Action#output` methods. They
need to be serializable to JSON so it should contain only combination of primitive Ruby types
like: `Hash`, `Array`, `String`, `Integer`, etc.

#### Triggering

Any action is triggered by calling:

``` ruby
world_instance.trigger(AnAction, *args)
```

which starts immediately planning the action in the same thread and returns after planning.

{% info_block %}

In Foreman and Katello actions are usually triggered by `ForemanTask.async_task` and
`ForemanTasks.async_task` so following part is not that important if you are using
`ForemanTasks`.

{% endinfo_block %}

`World#trigger` method returns object of `TriggerResult` type. Which is 
[Algebrick](http://blog.pitr.ch/projects/algebrick/) variant type where definition follows:

```ruby
TriggerResult = Algebrick.type do
  # Returned by #trigger when planning fails.
  PlaningFailed   = type { fields! execution_plan_id: String, error: Exception }
  # Returned by #trigger when planning is successful but execution fails to start.
  ExecutionFailed = type { fields! execution_plan_id: String, error: Exception }
  # Returned by #trigger when planning is successful, #future will resolve after
  # ExecutionPlan is executed.
  Triggered       = type { fields! execution_plan_id: String, future: Future }

  variants PlaningFailed, ExecutionFailed, Triggered
end
```

If you do not know `Algebrick` you can think about these as `Struct`s with types.
You can see how it's used to distinguish all the possible results 
[in ForemanTasks module](https://github.com/theforeman/foreman-tasks/blob/master/lib/foreman_tasks.rb#L20-L32).

#### Planning

Planning follows immediately after action is triggered. Planning always uses the tread 
triggering the action. Planning phase configures actions's input for run phase.
It starts by executing `plan` method of the action instance passing in 
arguments from `World#trigger method`

```ruby
world_instance.trigger(AnAction, *args)
# executes following
an_action.plan(*args) # an_action is AnAction
```

By default `plan` method plans itself if `run` method is present using first argument as input.

```ruby
class AnAction < Dynflow::Action
  def run
    output.update self.input
  end
end

world_instance.trigger AnAction, data: 'nothing'
```

The above will just plan itself copying input to output in run phase.

In most cases the `plan` method is overridden to plan self with transformed arguments and/or 
to plan other actions. Let's look at the argument transformation first:

```ruby
class AnAction < Dynflow::Action
  def plan(any_array)
    # pick just numbers
    plan_self numbers: any_array.select { |v| v.is_a? Number }
  end

  def run
    # compute sum - simulating a time consuming operation
    output.update sum: input[:numbers].reduce(&:+) 
  end
end
```

Now let's see an example with action planning:

```ruby
class SumNumbers < Dynflow::Action
  def plan(numbers)
    plan_self numbers: numbers
  end

  def run
    output.update sum: input[:numbers].reduce(&:+)
  end
end

class SumManyNumbers < Dynflow::Action
  def plan(numbers)
    # references to planned actions
    planned_sub_sum_actions = numbers.each_slice(10).map do |numbers|
      plan_action SumNumbers, numbers
    end

    # prepare array of output references where each points to sum in the 
    # output of particular action
    sub_sums = planned_sub_sum_actions.map do |action|
      action.output[:sum]
    end

    # plan one last action which will sum the sub_sums
    # it depends on all planned_sub_sum_actions because it uses theirs outputs
    plan_action SumNumbers, sub_sums
  end
end

world_instance.trigger SumManyNumbers, (1..100).to_a
```

Above example will in parallel sum numbers by slices of 10 values: first action sums `1..10`,
second action sums `11..20`, ..., tenth action sums `91..100`. After all sub sums are computed
one final action sums the sub sums into final sum.

{% warning_block %}

This example is here to demonstrate the planning abilities. In reality this paralyzation of 
compute intensive tasks does not have a positive effect on Dynflow running on MRI. The pool of
workers may starve. It is not a big issue since Dynflow is mainly used to orchestrate external 
services.

*TODO add link to detail explanation in How it works when available.*

{% endwarning_block %}

#### Running TODO

*TODO*

-   does not touches input just uses it
-   defines output

#### Finalizing TODO

*TODO*

-   does not touches input or output just uses it

*TODO bellow to be refined*

-   input/output
-   it's kind a dirty function

```ruby
# every action needs to inherit from Dynflow::Action
class Action < Dynflow::Action

  # OPTIONAL: the input format for the execution phase of this action
  # (https://github.com/iNecas/apipie-params for more details.
  # Validations can be performed against this description (turned off
  # for now)
  input_format do
    param :id, Integer
    param :name, String
  end

  # OPTIONAL: every action can produce an output in the execution
  # phase. This allows to describe the output.
  output_format do
    param :uuid, String
  end

  # OPTIONAL: this specifies that this action should be performed when
  # AnotherAction is triggered.
  def self.subscribe
    AnotherAction
  end

  # OPTIONAL: executed during the planning phase. It's possible to
  # specify explicitly the workflow here. By default it schedules just
  # this action.
  def plan(object_1, object_2)
    # +plan_action+ schedules the SubAction to be part of this
    # workflow
    # the +object_1+ is passed to the +SubAction#plan+ method.
    plan_action SubAction, object_1
    # we can specify, where in the workflow this action should be
    # placed, as well as prepare the input.
    plan_self { id: object_2.id, name: object_2.name}
  end

  # OPTIONAL: run the execution part of this action. Transform the
  # data from +input+ to +output+. When not specified, the action is
  # not used in the execution phase.
  def run
    output[:uuid] = "#{input[:name]}-#{input[:id]}"
  end

  # OPTIONAL: finalize the action after the execution phase finishes.
  # in the +input+ and +output+ attributes are available the data from
  # execution phase. in the +outputs+ argument, all the execution
  # phase actions are available, each providing its input and output.
  def finalize
    puts output[:uuid]
  end
end
```

### Dependencies

As already mentioned, actions can use output of different actions as their input (or just parts).
When they does it creates dependency between actions.

```ruby
def plan
  first_action  = plan_action AnAction
  second_action = plan_action AnAction, first_action.output[:a_key_in_output]
end
```

`second_action` uses part of the `first_action`'s output 
therefore it depends on the `first_action`.

If actions are planned without this dependency as follows

```ruby
def plan
  first_action  = plan_action AnAction
  second_action = plan_action AnAction
end
```

then they are independent and they are executed concurrently.

There is also other mechanism how to describe dependencies between actions than just
the one based on output usage. Dynflow user can specify the order between planned 
actions with DSL methods `sequence` and `concurrence`. Both methods are taking blocks
and they specify how actions planned inside the block 
(or inner `sequence` and `concurrence` blocks) should be executed. 

By default `plan` considers it's space as inside `concurrence`. Which means

```ruby
def plan
  first_action  = plan_action AnAction
  second_action = plan_action AnAction
end
```
equals

```ruby
def plan
  concurrence do
    first_action  = plan_action AnAction
    second_action = plan_action AnAction
  end
end
``` 

You can establish same dependency between `first_action` and `second_action` without 
using output by using `sequnce`

```ruby
def plan
  sequence do
    first_action  = plan_action AnAction
    second_action = plan_action AnAction
  end
end
```

As mentioned the `sequence` and `concurrence` methods can be nested and mixed 
with output usage to create more complex dependencies. Let see commented example:

```ruby
def plan
  # Plans 3 actions of type AnAction to be executed in sequence
  # argument is the index in the sequence.
  actions_executed_sequentially = sequence do
    3.times.map { |i| plan_action AnAction, i }
  end

  # Depends on output of the last action in `actions_executed_sequentially`
  # so it's added to the above sequence to be executed as 4th.
  action1 = plan_action AnAction, actions_executed_sequentially.last.output

  # It's planed in default plan's concurrency scope it's executed concurrently
  # to about four actions.
  action2 = plan_action AnAction  
end
```

The order than will be:

-   concurrently: 
    -   sequentially:
        1.  `*actions_executed_sequentially`
        1.  `action1`
    -   `action2`

Let's see one more example:

```ruby
def plan
  actions = sequence do
    2.times.map do |i|
      concurrency do
        2.times.map { plan_action AnAction, i }
      end
    end
  end
end
```
Which results in order of execution:

-   sequentially:
    1.  concurrently:
        -   `actions[0][0]` argument: 0
        -   `actions[0][1]` argument: 0
    1.  concurrently:
        -   `actions[1][0]` argument: 1
        -   `actions[1][1]` argument: 1
    
{% info_block %}

It's on our todo-list to change that to be able to define acyclic-graph of dependencies
between the actions. `sequence` and `concurrence` methods will then be deprecated and kept
just for backward compatibility.

{% endinfo_block %}

{% warning_block %}

Internally dependencies are also modeled with objects representing Sequences and Concurrences,
which makes it weaker than acyclic-graph so in some cases during the dependency resolution
it may lead into not the most effective execution plan. Some actions will run in sequence even 
though they could be run concurrently.

{% endwarning_block %}


### Database transactions TODO

*TODO*

-   DB should be modified and read only in `plan` and `finalize`
-   transaction adapters

### Composition

Dynflow is designed to allow easy composition of small building blocks
called `Action`s. Typically there are actions composing smaller pieces 
together and other actions doing actual steps of work as in following
example:

```ruby
class CreateInfrastructure < Dynflow::Action
  def plan
    sequence do
      concurrence do
        plan_action(CreateMachine, 'host1', 'db')
        plan_action(CreateMachine, 'host2', 'storage')
      end
      plan_action(CreateMachine,
                  'host3',
                  'web_server',
                  :db_machine      => 'host1',
                  :storage_machine => 'host2')
    end
  end
end
```
Action `CreateInfrastructure` does not have a `run` method defined, it only
defines `plan` action where other actions composed together.

### Subscriptions

Even though composing actions is quite ease and allows to decompose
business logic to small pieces it does not directly support extensions
by plugins. For that there are subscriptions.

`Actions` can subscribe from a plugin, gem, any other library to already
loaded `Actions`, doing so they extend the planning process with self.

Lets look at an example starting by definition of a core action

```ruby
# This action can be extended without doing any 
# other steps to support it.
class ACoreAppAction < Dynflow::Action
  def plan(arguments)
    plan_self(args: arguments)
    plan_action(AnotherCoreAppAction, arguments.first)
  end

  def run
    puts "Running core action: #{input[:args]}"
    self.output.update success: true
  end
end
```

followed by an action definition defined in a plugin/gem/etc.

```ruby
class APluginAction < Dynflow::Action
  # plan this action whenever ACoreAppAction action is planned
  def self.subscribe
    ACoreAppAction
  end

  def plan(arguments)
    arguments # are same as in ACoreAppAction#plan
    plan_self(args: arguments)
  end

  def run
    puts "Running plugin action: #{input[:args]}"
  end
end
```

Subscribed actions are planned with same arguments as action they are
subscribing to which is called `trigger`. Their plan method is called right
after planning of the triggering action finishes.

It's also possible to access target action and use its output which 
makes it dependent (running in sequence) on triggering action.

```ruby
def plan(arguments)
  plan_self trigger_success: trigger.output[:success]
end

def run
  self.output.update 'trigger succeeded' if self.input[:trigger_success]
end
```

Subscription is designed for extension by plugins, it should **not** be used
inside a single library/app-module. It would make the process definition 
hard to follow (all subscribed actions would need to be looked up).

### Suspending

Sometimes action represents tasks taken in different services, 
(e.g. repository synchronization in [Pulp](http://www.pulpproject.org/)).
Dynflow tries not to waste computer resources so it offers tools to free 
threads to work on other actions while waiting on external tasks or events.

Dynflow allows actions to suspend and be woken up on external events. 
Lets create a simulation of an external service before showing the example
of suspending action.

```ruby
class AnExternalService
  def start_synchronization(report_to)
    Thread.new do
      sleep 1
      report_to << :done
    end
  end
end
```

The `AnExternalService` can be invoked to `start_synchronization` and it will
report back a second later to action passed in argument `report_to`. It sends
event `:done` back by `<<` method.

Lets look at an action example.

```ruby
class AnAction < Dynflow::Action
  EXTERNAL_SERVICE = AnExternalService.new

  def plan
    plan_self
  end

  def run(event)
    case event
    when nil # first run
      suspend do |suspended_action| 
        EXTERNAL_SERVICE.start_synchronization suspended_action 
      end
    when :done # external task is done
      output.update success: true
      # let the run phase finish normally
    else
      raise 'unknown event'
    end
  end
end
```
Which is then executed as follows:

1.  `AnAction` is triggered 
1.  It's planned.
1.  Its `run` phase begins.
1.  `run` method is invoked with no event (`nil`).
1.  Matches with case branch initiating the external synchronization.
1.  Action initializes the synchronization and pass in reference
    to suspended_action.
1.  Action is suspended, execution of the run method finishes immediately
    after `suspend` is called, its block parameter is evaluated right after
    suspending.
1.  Action is kept on memory to be woken up when events are received but it does not 
    block any threads.
1.  Action receives `:done` event through suspend action reference.
1.  `run` method is executed again with `:done` event.
1.  Output is updated with `success: true` and actions finishes `run` phase.
1.  There is no `finalize` phase, action is done.
 
This event mechanism is quite flexible, it can be used for example to build a 
[polling action abstraction](https://github.com/Dynflow/dynflow/blob/master/lib/dynflow/action/polling.rb)
which is a topic for next chapter.

### Polling

Not all services support callbacks to be registered which would allow to wake up suspended
actions only once at the end when the external task is finished. In that case we often 
need to poll the service to see if the task is still running or finished.

For that purpose there is `Polling` module in Dynflow. Any action can be turned into a polling one
just by including the module.

```ruby
class AnAction < Dynflow::Action
  include Dynflow::Action::Polling
```

There are 3 methods need to be always implemented:

-   `done?` - determines when the task is complete based on external task's data.
-   `invoke_external_task` - starts the external task.
-   `poll_external_task` - polls the external task status data and returns a status 
    (JSON serializable data like: `Hash`, `Array`, `String`, etc.) which are stored in action's
    output.
    
```ruby
  def done?
    external_task[:progress] == 1
  end
  
  def invoke_external_task
    triger_the_task_with_rest_call  
  end
  
  def poll_external_task
    data     = poll_data_with_rest_call
    progress = calculate_progress data # => a float in 0..1  
    { progress: progress
      data:     data }
  end
end
```

This action will do following in run phase:

1.  `invoke_external_task` on first run of the action
1.  suspends and then periodically:
    1.  wakes up
    1.  `poll_external_task`
    1.  checks if `done?`: 
        - `true` -> it concludes the run phase
        - `false` -> it schedules next polling
    
There are 2 other methods handling external task data which can optionally overridden:

-   `external_task` - reads the external task's stored data, by default it reads `self.output[:task]`
-   `external_task=` - writes the the external task's stored data, by default it writes to 
    `self.output[:task] = value`

There are also other features implemented like:

-   Gradual prolongation of the polling interval.
-   Retries on a poll failing.

Please see the 
[`Polling` module](https://github.com/Dynflow/dynflow/blob/master/lib/dynflow/action/polling.rb)
for more details.

### Error handling TODO

-   rescue strategy
-   resume

### Console TODO

### Testing TODO

### Short vs. long running actions TODO

### Middleware TODO

-   as current user example

### SubTasks TODO

## How it works TODO

### Action states TODO

### inter-worlds communication / multi-executors TODO

### Links to concurrent-ruby/algebrick TODO

### Thread-pools TODO

### Suspending -> events TODO

## Use cases TODO

-   Embedded without a DB, like inside CLI tool for a complex installation
-   reserve resources in planning do not try to do `if`s in run phase

## Comments

**Comments are temporally turned on here for faster feedback.**
