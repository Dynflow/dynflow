---
layout: page
title: Documentation
countheads: true
toc: true
comments: true
---

## High level overview

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


## Glossary

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

## How to use

### To be added

-   Examples
    -   for async operations
    -   for orchestrating system/ssh calls
    -   for keeping consistency between local database and external systems
    -   sub-tasks
-   Action anatomy
    -   Input/Output
-   Phases
-   ~~Actions composition~~
-   ~~subscribe/plugins~~
-   ~~Suspending~~
-   Polling action
-   Console
-   Testing
-   Error handling
    -   rescue strategy
    -   resume
-   Development vs production
-   Short vs. long running actions
-   Middleware
    -   as current user
-   SubTasks

### Action anatomy

*TODO to be refined*

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

### Action composition

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
Action `CreateInfrastructure` is does not have a `run` method defined, it only
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

3 methods need to be always implemented: `done?`, `invoke_external_task`, `poll_external_task`.

-   `done?` - determines when the task is complete based on external task's data.
-   `invoke_external_task` - starts the external task.
-   `poll_external_task` - polls the external task status data and returns a status 
    (JSON serializable data like: `Hash`, `Array`, `String`, etc.) which are stored in action's
    output.

*TODO finish example and `external_task`, `external_task=` methods description*
   
```ruby
  def done?
  end
  
  def invoke_external_task
  end
  
  def poll_external_task
  end
end
```

## How it works

### To be added

-   Action states
-   inter-worlds communication / multi-executors
-   Links to concurrent-ruby/algebrick
-   Thread-pools
-   Suspending -> events

## Use cases

*TODO*

-   Embedded without a DB, like inside CLI tool for a complex installation
-   reserve resources in planning do not try to do `if`s in run phase

## Comments

**Comments are temporally turned on here for faster feedback.**
