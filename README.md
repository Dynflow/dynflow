DYNamic workFLOW
================

In traditional workflow engines, you specify a static workflow and
then run it with various inputs. Dynflow takes different approach.

You specify the inputs and the workflow is generated on the fly. You
can either specify the steps explicitly or subscribe one action to
another. This is suitable for plugin architecture, where you can't
write the whole process on one place.

Dynflow doesn't differentiate between workflow and action. Instead,
every action can populate another actions, effectively producing the
resulting set of steps.

The whole execution is done in three phases:

1. *Planning phase*

  Construct the execution plan for the workflow. It's invoked by
  calling `trigger` on an action. Two mechanisms are used to get the set
  of actions to be executed:

    a. explicit calls of `plan_action` methods in the `plan` method

    b. implicit associations: an action A subscribes to an action B,
    which means that the action A is executed whenever the action B
    occurs.

The output of this phase is a set of actions and their inputs.

2. *Execution phase*

  The plan is being executed step by step, calling the run method of
  an action with corresponding input. The results of every action are
  written into output attribute.

  The run method should be stateless, with all the needed information
  included in the input from planning phase. This allows us to
  control the workflow execution: the state of every action can be
  serialized therefore the workflow itself can be persisted. This makes
  it easy to recover from failed actions by rerunning it.

3. *Finalization phase*

  Take the results from the execution phase and perform some additional
  tasks. This is suitable for example for recording the results into
  database.

Every action can participate in every phase.

Example
-------

One code snippet is worth 1000 words:

```ruby
# The anatomy of action class

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
    plan_self {'id' => object_2.id, 'name' => object_2.name}
  end

  # OPTIONAL: run the execution part of this action. Transform the
  # data from +input+ to +output+. When not specified, the action is
  # not used in the execution phase.
  def run
    output['uuid'] = "#{input['name']}-#{input['id']}"
  end

  # OPTIONAL: finalize the action after the execution phase finishes.
  # in the +input+ and +output+ attributes are available the data from
  # execution phase. in the +outputs+ argument, all the execution
  # phase actions are available, each providing its input and output.
  def finalize(outputs)
    puts output['uuid']
  end
end
```

One can generate the execution plan for an action without actually
running it:

```ruby
pp Publish.plan(short_article).actions
# the expanded workflow is:
# [
#  Publish: {"title"=>"Short", "body"=>"Short"} ~> {},
#  Review:  {"title"=>"Short", "body"=>"Short"} ~> {},
#  Print:   {"title"=>"Short", "body"=>"Short", "color"=>false} ~> {}
# ]
```

Therefore it's suitable for the plan methods to not have any side
effects (except of database writes that can be roll-backed)

In the finalization phase, `finalize` method is called on every action
if defined. The order is the same as in the execution plan.

Every action should be as atomic as possible, providing better
granularity when manipulating the process. Since every action can be
subscribed by another one, adding new behaviour to an existing
workflow is really simple.

The input and output format can be used for defining the interface
that other developers can use when extending the workflows.

See the examples directory for more complete examples.

License
-------

MIT

Author
------

Ivan Nečas
