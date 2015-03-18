![Dynflow](doc/pages/source/images/logo-long.png)
=======

![Build](https://img.shields.io/travis/Dynflow/dynflow/master.svg?style=flat)
![Issues](https://img.shields.io/github/issues/Dynflow/dynflow.svg?style=flat)
![Gem version](https://img.shields.io/gem/v/dynflow.svg?style=flat)
![License](https://img.shields.io/badge/license-MIT-brightgreen.svg?style=flat)

**Note:** *There is a project page and documentation being build in url <http://dynflow.github.io/>.
It's still work in progress but you may find useful information there. It'll eventually replace 
this README.*

[Dynflow [DYN(amic work)FLOW]](http://dynflow.github.io/) is a workflow engine
written in Ruby that allows to:

* keep track of the progress of running process
* run the code asynchronously
* resume the process when something goes wrong, skip some steps when needed
* detect independent parts and run them concurrently
* compose simple actions into more complex scenarios
* extend the workflows from third-party libraries
* keep consistency between local transactional database and
  external services
* suspend the long-running steps, not blocking the thread pool
* cancel steps when possible
* extend the actions behavior with middlewares
* define the input/output interface between the building blocks (planned)
* define rollback for the workflow (planned)
* have multiple workers for distributing the load (planned)

Dynflow doesn't try to choose the best tool for the jobs, as the right
tool depends on the context. Instead, it provides interfaces for
persistence, transaction layer or executor implementation, giving you
the last word in choosing the right one (providing default
implementations as well).

![Screenshot](doc/images/screenshot.png)

* [Documentation](http://dynflow.github.io/documentation/) *in progress*
* [Current status](#current-status)
* [How it works](#how-it-works)
* [Examples](#examples)
* [The Anatomy of Action Class](#the-anatomy-of-action-class)
* [Glossary](#glossary)
* [Related projects](#related-projects)

Current status
--------------

Dynflow has been under heavy development for several months to be able
to support the services orchestration in the
[Katello](http://katello.org) and [Foreman](http://theforeman.org/)
projects, getting to production-ready state in couple of weeks.

How it works
------------

In traditional workflow engines, you specify a static workflow and
then run it with various inputs. Dynflow takes different approach.
You specify the inputs and the workflow is generated on the fly. You
can either specify the steps explicitly or subscribe one action to
another. This is suitable for plugin architecture, where you can't
write the whole process on one place.

Dynflow doesn't differentiate between workflow and action. Instead,
every action can populate another actions. This allows composing
more simpler workflows into a big one.

The whole execution is done in three phases:

1. *Plan phase*

  Construct the execution plan for the workflow. Two mechanisms are
  used to get the set of actions to be executed:

    a. explicit calls of `plan_action` methods in the `plan` method

    b. implicit associations: an action A subscribes to an action B,
    which means that the action A is executed whenever the action B
    occurs.

The output of this phase is a set of actions and their inputs.

2. *Run phase*

  The plan is being executed step by step, calling the run method of
  an action with corresponding input. The results of every action are
  written into output attribute.

  The run method should be stateless, with all the needed information
  included in the input from planning phase. This allows us to
  control the workflow execution: the state of every action can be
  serialized therefore the workflow itself can be persisted. This makes
  it easy to recover from failed actions by rerunning it.

3. *Finalize phase*

  Take the results from the execution phase and perform some additional
  tasks. This is suitable for example for recording the results into
  database.

Every action can participate in every phase.

Examples
--------

The `examples` directory contains simple ruby scripts different
features in action. You can just run the example files and see the Dynflow
in action.

* `orchestrate.rb` - example worlflow of getting some infrastructure
  up and running, with ability to rescue from some error states.

* `orchestrate_evented.rb` - the same workflow using the ability to
  suspend/wakeup actions while waiting for some external event.
  It also demonstrates the ability to cancel actions that support it.

* `remote_executor.rb` - example of executing the flows in external
  process


The Anatomy of Action Class
---------------------------

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
Every action should be as atomic as possible, providing better
granularity when manipulating the process. Since every action can be
subscribed by another one, adding new behaviour to an existing
workflow is really simple.

The input and output format can be used for defining the interface
that other developers can use when extending the workflows.

Glossary
--------

* **action** - building block for the workflows: a Ruby class
    inherited from `Dynflow::Action`. Defines code to be run in
    plan/run/finalize phase. It has defined input and output data.
* **execution plan** - definition of the workflow: product of the plan
    phase
* **trigger an action** - entering the plan phase, starting with the
    `plan` method of the action. The execution follows immediately.
* **plan_self** - converts the arguments of the `plan` method into
    action input, that can be accessed from the `run`/`finalize`
    phase.
* **plan_action** - includes another action into the workflow, passing
    the arguments into the `plan` method of the action
* **step** - execution unit of the action. It represents the action in
    specific phase (plan step, run step, finalize step).
* **flow** - definition of the run/finalize phase, holding the
    information about steps that can run concurrently/in sequence.
    Part of execution plan.
* **executor** - service that executes the run and finalize flows
    based on the execution plan. It can run in the same process as the
    plan phase or in different process (using the remote executor)
* **world** - the universe where the Dynflow runs the code: it holds
    all needed configuration.

Related projects
----------------

* [Foreman](http://theforeman.org) - lifecycle management tool for
  physical and virtual servers

* [Katello](http://katello.org) - content management plugin for
  Foreman: integrates couple of REST services for managing the
  software updates in the infrastructure.

* [Foreman-tasks](https://github.com/iNecas/foreman-tasks) - Foreman
  plugin providing the tasks management with Dynflow on the back-end

* [Dyntask](https://github.com/iNecas/dyntask) - generic Rails engine
  providing the tasks management features with Dynflow on the back-end

* [Sysflow](https://github.com/iNecas/sysflow) - set of reusable tools
   for running system tasks with Dynflow, comes with simple Web-UI for
   testing it


Requirements
------------

-   Ruby MRI 1.9.3, 2.0, or 2.1.
-   It does not work on JRuby nor Rubinius yet.


License
-------

MIT

Authors
-------

Ivan Nečas, Petr Chalupa
