---
layout: page
title: Documentation
countheads: true
toc: true
---

## High level overview

*TODO*

## Glossary

*TODO to be refined*

-   **Action** - building block for the workflows: a Ruby class inherited from
    `Dynflow::Action`. Defines code to be run in plan/run/finalize phase. It has
    defined input and output data.
-   **Execution plan** - definition of the workflow: product of the plan phase
-   **Triggering an action** - entering the plan phase, starting with the plan
    method of the action. The execution follows immediately.
-   **Phase** - (plan step, run step, finalize step).
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
    -   input/output
-   ~~Actions composition~~
    -   ~~subscribe/plugins~~
-   Suspending
-   Polling action
-   Phases
-   Console
-   Testing
-   Error handling
    -   rescue strategy
    -   resume
-   Development vs production
-   Short vs. long running actions
-   Middleware
    -   as current user

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

## Actions composition

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
