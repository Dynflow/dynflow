---
layout: page
title: Documentation
countheads: true
toc: true
comments: true
---

{% danger_block %}

Work in progress! It contains a lot of tpyos, please let us know. There are comments at the bottom
or you can submit a PR against [pages branch](https://github.com/dynflow/dynflow/tree/pages).

Please help with the documentation if you know Dynflow.

Thanks!

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

## Glossary

-   **Action** - building block of execution plans, a Ruby class inherited
    from `Dynflow::Action`, defines code to be run in each phase.
-   **Phase** - Each action has three phases: `plan`, `run`, `finalize`.
-   **Input** - A `Hash` of data coming to the action.
-   **Output** - A `Hash` of data that the action produces. It's
    persisted and can be used as input of other actions.
-   **Execution plan** - definition of the workflow: product of the plan phase,
-   **Triggering an action** - entering the plan phase, starting with the plan
    method of the action. The execution follows immediately.
-   **Flow** - definition of the `run`/`finalize` phase, holding the information
    about steps that can run concurrently/in sequence. Part of execution plan.
-   **Executor** - service that executes the run and finalize flows based on
    the execution plan. It can run in the same process as the plan phase or in
    different process (using the remote executor).
-   **World** - the universe where the Dynflow runs the code: it holds all
    needed configuration. Usually there's only one world per Dynflow process,
    besides configuration it also holds `Persistence`, `Logger`, `Executor` and
    all the other objects necessary for action executing. This concept
    allows us to avoid globally shared state. Also, the worlds can
    talk to each other, which is helpful for production and
    high-availability setups,
    having multiple worlds on different hosts handle the execution of the execution plans.

##  Examples

See the
[examples directory](https://github.com/Dynflow/dynflow/tree/master/examples)
for the code in action. Running those files (except the
`example_helper.rb` file) leads to the Dynflow runtime being initialized
(including the web console where one can explore the features and
experiment).

*TODO*

-   for async operations
-   for orchestrating system/ssh calls
-   for keeping consistency between local database and external systems
-   sub-tasks

## How to use

### World creation TODO

-   *include executor description*

### Development vs production

-   *In development execution runs in the same process, in production there is an
    executor process.*

*TODO*

### Action anatomy

{% digraph %}
rankdir=LR
Trigger -> Plan -> Run -> Finalize
{% enddigraph %}

When action is triggered, Dynflow executes plan method on this action, which
is responsible for building the execution plan. It builds the execution plan by calling
`plan_action` and `plan_self` methods, effectively listing actions that should be run as
a part of this execution plan. In other words, it compiles a list of actions on which
method `run` will be called. Also it's responsible for giving these actions
an order. A simple example of such plan action might look like this

```ruby
# this would plan deletion of files passed as an input array
def plan(files)
  files.each do |filename|
    plan_action MyActions::File::Destroy, filename
  end
end
```

Note that it does not have to be only other actions that are planned to run.
In fact it's very common that the action plans itself, which means it will
put its own `run` method call in the execution plan. In order to do that
you can use `plan_self`. This could be used in MyActions::File::Destroy
used in previous example

```ruby
class MyActions::File::Destroy < Dynflow::Action
  def plan(filename)
    plan_self path: filename
  end

  def run
    File.rm(input.fetch(:path))
  end
end
```

In example above, it seems that `plan_self` is just shortcut to
`plan_action MyActions::File::Destroy, filename` but it's not entirely true.
Note that `plan_action` always triggers `plan` of a given action while `plan_self`
plans only the `run` and `finalize` of Action, so by using `plan_action`
we'd end up in endless loop.

Also note, that run method does not take any input. In fact, it can use
`input` method that refers to arguments, that were used in `plan_self`.

Similar to the input mentioned above, the run produces output.
After that some finalizing steps can be taken. Actions can use outputs of other actions
as parts of their inputs establishing dependency. Action's state is serialized between each phase
and survives machine/executor restarts.

As lightly touched in the previous paragraphs there are 3 phases: `plan`, `run` and `finalize`.
Plan phase starts by triggering an action. `run` and `finalize` are only ran if you use
`plan_self` in `plan` phase.

#### Input and Output

Both input and output are `Hash`es accessible by `Action#input` and `Action#output` methods. They
need to be serializable to JSON so it should contain only combination of primitive Ruby types
like: `Hash`, `Array`, `String`, `Integer`, etc.


{% warning_block %}

One should avoid using directly

```ruby
self.output = { key: data }
```

It might delete other data stored in the output (potentially by middleware and other
parts of the action). Therefore it's preferred to use

```ruby
output.update(key: data, another_key: another_data)
# or for one key
output[:key] = data
```

{% endwarning_block %}

{% info_block %}

You may sometime find these input/output format definitions:

```ruby
class AnAction < Dynflow::Action
  input_format do
    param :id, Integer
    param :name, String
  end

  output_format do
    param :uuid, String
  end
end
```

This might me quite handy especially in combination with
[subscriptions](#subscriptions) functionality.

The format follows [apipie-params](https://github.com/iNecas/apipie-params) for more details.
Validations of input/output could be performed against this description but it's not turned on
by default. (It needs to be revisited and updated to be fully functional.)

{% endinfo_block %}

#### Triggering

Triggering the action means starting the plan phase, followed by immediate execution.
Any action is triggered by calling:

``` ruby
world_instance.trigger(AnAction, *args)
```

{% info_block %}

In Foreman and Katello actions are usually triggered by `ForemanTask.sync_task` and
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
  # Returned by #delay when scheduling succeeded.
  Scheduled       = type { fields! execution_plan_id: String }
  # Returned by #trigger when planning is successful, #future will resolve after
  # ExecutionPlan is executed.
  Triggered       = type { fields! execution_plan_id: String, future: Future }

  variants PlaningFailed, ExecutionFailed, Triggered
end
```

If you do not know `Algebrick` you can think about these as `Struct`s with types.
You can see how it's used to distinguish all the possible results
[in ForemanTasks module](https://github.com/theforeman/foreman-tasks/blob/master/lib/foreman_tasks.rb#L20-L32).

```ruby
def self.trigger_task(async, action, *args, &block)
  Match! async, true, false

  match trigger(action, *args, &block),
        # Raise if there is any error caused either by failed planning or
        # by faild start of execution.
        (on ::Dynflow::World::PlaningFailed.(error: ~any) |
                ::Dynflow::World::ExecutionFailed.(error: ~any) do |error|
          raise error
        end),
        # Succesfully triggered.
        (on ::Dynflow::World::Triggered.(
              execution_plan_id: ~any, future: ~any) do |id, finished|
          # block on the finished Future if this is called synchronously
          finished.wait if async == false
          return ForemanTasks::Task::DynflowTask.find_by_external_id!(id)
        end)
end
```

#### Scheduling

Scheduling an action means setting it up to be triggered at set time in future.
Any action can be delayed by calling:

```ruby
world_instance.delay(AnAction,
                     { start_at: Time.now + 360, start_before: Time.now + 400 },
                     *args)
```

This snippet of code would delay `AnAction` with arguments `args` to be executed
in the time interval between `start_at` and `start_before`. Setting `start_before` to `nil`
would delay execution of this action without the timeout limit.

When an action is delayed, an execution plan object is created with state set
to `scheduled`, but it doesn't run the the plan phase yet, the planning happens
when the `start_at` time comes. If the planning doesn't happen in time
(e.g. after `start_before`), the execution plan is marked as failed
(its state is set to `stopped` and result to `error`).

Since the `args` have to be saved, there must be a mechanism to safely serialize and deserialize them
in order to make them survive being saved in a database. This is handled by a serializer.
Different serializers can be set per action by overriding its `delay` method.

Planning of the delayed plans is handled by `DelayedExecutor`, an object which
periodically checks for delayed execution plans and plans them. Scheduled execution
plans don't do anything by themselves, they just wait to be picked up and planned by a DelayedExecutor.
It means that if no DelayedExecutor is present, their planning will be delayed until a scheduler
is spawned.

#### Plan phase

Planning always uses the thread triggering the action. Plan phase
configures action's input for run phase. It starts by executing
`plan` method of the action instance passing in arguments from
`World#trigger method`

```ruby
world_instance.trigger(AnAction, *args)
# executes following
an_action.plan(*args) # an_action is AnAction
```

`plan` method is inherited from Dynflow::Action and by default it plans itself if
`run` method is present using first argument as input. It also calls `finalize`
method if it is present.

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
to plan other actions. In the Rails application, the arguments of the
plan phase are often the ActiveRecord objects, that are then
used to produce the inputs for the actions.

Let's look at the argument transformation first:

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

{% info_block %}

It's considered a good practice to use just enough data for the
input for the action to perform the job. That means not too much
(such as using ActiveRecord's attributes), as it might have
performance impact as well as causes issues when changing the
attributes later.

 On the other hand, the input should contain enough data to perform
the job without the need for reaching to external sources. Therefore,
instead of passing just the ActiveRecord id and loading the whole
record again in run phase, just to use some attributes, it's better to
use these attributes directly as input of the action.

Following theses rules should lead to the best results, both from
readability and performance point of view.

{% endinfo_block %}

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

This example is here to demonstrate the planning abilities. In reality this parallelization of
compute intensive tasks does not have a positive effect on Dynflow running on MRI. The pool of
workers may starve. It is not a big issue since Dynflow is mainly used to orchestrate external
services.

*TODO add link to detail explanation in How it works when available.*

{% endwarning_block %}

Action may access local DB in plan phase,
see [Database and Transactions](#database-and-transactions).

#### Run phase

Actions has a run phase if there is `run` method implemented.
(There may be actions just planning other actions.)

The run method implements the main piece of work done by this action converting
input into output. Input is immutable in this phase. It's the right place for all the steps
which are likely to fail. Action `run` phase are allowed to have side effects like: file operations,
calls to other systems, etc.
Local DB should not be accessed in this phase,
see [Database and Transactions](#database-and-transactions)

#### Finale phase

Main purpose of `finalize` phase is to be able access local DB after action finishes
successfully, like: indexing based on new data, updating records as fully created, etc.
Finalize phase does not modify input or output of the action.
Action may access local DB in `finalize` phase and must be **idempotent**,
see [Database and Transactions](#database-and-transactions).

### Dependencies

As already mentioned, actions can use output of different actions as their input (or just parts).
When they do it creates dependency between actions, which is automatically detected
by Dynflow and the execution plan is built accordingly.

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

By default `plan` considers its space as inside `concurrence`. Which means

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
using output by using `sequence`

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

  # It's planned in default plan's concurrency scope so it's executed concurrently
  # with the other four actions.
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
it might not lead into the most effective execution plan. Some actions will run in sequence even
though they could be run concurrently. This limitation is likely to be
removed in some of the further releases.

{% endwarning_block %}

### Database and Transactions

Dynflow was designed to help with orchestration of other services.
The usual execution looks as follows, we use an ActiveRecord User as example of a resource.

1.  Trigger user creation, argument is an unsaved ActiveRecord user object
1.  Planning: The user is stored in local DB (in the Dynflow hosting application) within the
    `plan` phase. The record is marked as incomplete.
1.  Running: Operations needed for the user in external services with (e.g.) REST call.
    The phase finishes when the all the external calls succeeded successfully.
1.  Finalizing: The record in local DB is marked as done: ready to be
    used. Potentially, saving some data that were retrieved in the `run`
    phase back to the local database.

For that reason there are transactions around whole `plan` and `finalize` phase
(all action's plan methods are in one transaction).
If anything goes wrong in the `plan` phase any change made during planning to local DB is
reverted. Same holds for finalizing, if anything goes wrong, all changes are reverted. Therefore
all finalization methods has to be **idempotent**.

Internally Dynflow uses Sequel as its ORM, but users may choose what they need
to access they data. There is an interface `TransactionAdapters::Abstract` where its
implementations may provide transactions using different ORMs.
The most common one probably being `TransactionAdapters::ActiveRecord`.

So in the above example 2. and 4. step would be wrapped in `ActiveRecord` transaction
if `TransactionAdapters::ActiveRecord` is used.

Second outcome of the design is convention when actions should be accessing local Database:

-   **allowed** - in `plan` and `finalize` phases
-   **disallowed** - (or at least discouraged) in the `run` phase

{% warning_block %}

*TODO warning about AR pool configuration, needs to have sufficient size*

{% endwarning_block %}

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

Even though composing actions is quite easy and allows to decompose
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
    # arguments are same as in ACoreAppAction#plan
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

### States

Each **Action phase** can be in one of the following states:

-   **Pending** - Not yet executed.
-   **Running** - An action phase id being executed right now.
-   **Success** - Execution of an action phase finished successfully.
-   **Error** - There was an error during execution.
-   **Suspended** - Only `run` phase, when action sleeps waiting for events to be woken up.
-   **Skipped** - Failed actions can be marked as skipped allowing rest of the
    execution plan to finish successfully.
-   **Skipping** - Action is marked for skipping but execution plan was not yet
    resumed to mark it as Skipped.

**Execution plan** has following states:

-   **Pending** - Planning did not start yet.
-   **Scheduled** - Scheduled for later execution, not yet planned.
-   **Planning** - It's being planned.
-   **Planned** - It've been planned, running phase did not start yet.
-   **Running** - It's running, `run` and `finalize` phases of actions are executed.
-   **Paused** - It was paused when running. Happens on error or executor restart.
-   **Stopped** - Execution plan is completed.

**Execution plan** also has following results:

-   **Success** - Everything finished without error or skips.
-   **Warning** - When there are skipped steps.
-   **Error** - When one or more actions failed.
-   **Pending** - Execution plan still runs.

*TODO how do I access such states as a programmer?*
*TODO which Action phase states are "finish" and which requires user interaction?*

### Error handling

If an error is raised in **`plan` phase**, it is persisted in the Action object
for later inspection and it bubbles up in `World#trigger` method which was used to trigger
the action leading to this error.
If you compare it to errors raised during `run` and `finalize` phase,
there's one major difference: Those never bubble up in `trigger` because they are running
in executor not in triggering Thread, they are persisted just in the Action object.

If there is an error in **`run` phase**, the execution pauses. You can inspect the error in
[console](#console). The error may be intermittent or you may fix the problem manually. After
that the execution plan can be resumed and it'll continue by rerunning the failed action and
continuing with the rest of the actions. During fixing the problem you may also do the steps
in the actions manually, in that case the failed action can be also marked as skipped. After
resuming the skipped action is not executed and the execution plan continues with the rest.

If there is an error in **`finalize` phase**, whole `finalize` phase for all the actions is
rollbacked and can be rerun when the problem is fixed by resuming.

If you encounter an error during run phase `error!` or usual `raise` can be used.

#### Rescue strategy TODO

### Console TODO

-   *where to access*
-   *screenshots*

### Testing TODO

-   *testing helper methods*
-   *examples*
-   *see [testing of testing](https://github.com/Dynflow/dynflow/blob/master/test/testing_test.rb)*

### Long-running actions

Dynflow was designed as an Orchestration tool, parallelization of heavy CPU computation tasks
was not directly considered. Even with multiple executors single execution plan always runs
on one executor, so without JRuby it wont scale well (MRI's GIL). However JRuby support
should be added soon (TODO update when merged).

Another problem with long-running actions are blocked worker. Executor has only a limited pool of
workers, if more of them become busy it may result in worsen performance.

Blocking actions for long time are also problematic.

Solutions are:

-   **Using action suspending** - suspending the action until a condition is met,
    freeing the worker.
-   **Offloading computation** - CPU heavy parts can be offloaded to different services
    notifying the suspended actions when the computation is done.

### Middleware

Each action class has chain of middlewares which wrap phases of the action execution.
It's very similar to rack middlewares.
To create new middleware inherit from `Dynflow::Middleware` class. It has 5 methods which can be
overridden: `plan`, `run`, `finalize`, `plan_phase`, `finalize_phase`. Where the default
implementation for all the methods looks as following

```ruby
def plan(*args)
  pass *args
end
```

When overriding user can insert code before and/or after the `pass` method which executes next
middleware in the chain or the action itself which is at the end of the chain. Most usually the
`pass` is always called somewhere in the overridden method. There may be some cases when it can
be omitted, then it'll prevent all following middlewares and action from running.

Some implementation examples:
[KeepCurrentUser](https://github.com/theforeman/foreman-tasks/blob/master/app/lib/actions/middleware/keep_current_user.rb),
[Action::Progress::Calculate](https://github.com/Dynflow/dynflow/blob/master/lib/dynflow/action/progress.rb#L13-L42).

Each Action has a chain of middlewares defined. Middleware can be added by calling `use`
in the action class.

```ruby
class AnAction < Dynflow::Action
  use AMiddleware, after: AnotherMiddleware
end
```

Method `use` understands 3 option keys:

-   `:before` - makes this middleware to be ordered before a given middleware
-   `:after` - makes this middleware to be ordered after a given middleware
-   `:replace` - this middleware will replace given middleware

The `:before` and `:after` keys are used to build a graph from the middlewares which is then
sorted down with
[topological sort](http://ruby-doc.org//stdlib-2.0/libdoc/tsort/rdoc/TSort.html)
to the chain of middleware execution.

### Sub-plans

-   *when to use?*
-   *how to use?*

## How it works TODO

{% info_block %}
This part is based on the current work-in-progress on [multi-executors
support](https://github.com/Dynflow/dynflow/pull/139)
{% endinfo_block %}

### Action states TODO

-   *normal phases and Present phase*
-   *how to walk the execution plan*

### The world anatomy

The world represents the Dynflow's run-time and it acts as an external
interface. It holds all the configuration and sub-components needed for the
Dynflow to perform its job.

The Dynflow worlds is composed of the following sub-components:

1. **persistence** - provides the durability functionality: see
[persistence](#persistence)
1. **coordinator** - provides the coordination between worlds: see [coordinator](#coordinator)
1. **connector** - provides messages passing between worlds: see [connector](#connector)
1. **executor** - the run-time itself executing the execution plan. Not
every worlds has to have the executor present (there might be pure
client worlds: useful in production, see [develpment vs. production](#development-vs-production).
1. **client dispatcher** - responsible for communication between
client requests and other worlds
1. **executor dispatcher** - responsible for getting requests from
other worlds and sending the responses
1. **delayed executor** - responsible for planning and exectuion of scheduled tasks

{% plantuml %}

actor client

frame "world" {
interface adapter as PersistenceAdapter
interface adapter as CoordinatorAdapter
interface adapter as ConnectorAdapter
[coordinator] -up-> CoordinatorAdapter
[connector] -up-> ConnectorAdapter
[persistence] -up-> PersistenceAdapter
[connector] <-- [client dispatcher]
[connector] <-- [executor dispatcher]
[executor] <-- [executor dispatcher]
[coordinator] <-- [client dispatcher]
[coordinator] <-- [executor dispatcher]
[persistence] <-- [executor]
client -left--> [client dispatcher]
client -left--> [persistence]
}

{% endplantuml %}

The underlying technologies are hidden behind adapters abstraction,
which allows choosing the right technology for the job, while keeping
the rest of the Dynflow intact.

### Client world vs. executor world

In the simplest case, the world handles both the client requests and
the execution itself. This is useful for small all-in-one deployments
and development.

In production, however, one might want to separate
the client worlds (often running in the web-server process or client
library) and the executor worlds (running as part of standalone
service). This setup makes the execution more stable and
high-available (in active-active mode).

There might be multiple client as well as executor worlds in the
Dynflow infrastructure.

The executor world has still its own client dispatcher, so that it
can act as a client for triggering other execution plans (useful in
[sub-plans](#sub-plans) feature).

{% plantuml %}

actor client

frame "client world" {
  interface adapter as ClientPersistenceAdapter
  interface adapter as ClientCoordinatorAdapter
  interface adapter as ClientConnectorAdapter
  component [coordinator] as ClientCoordinator
  component [persistence] as ClientPersistence
  component [connector] as ClientConnector
  component [client dispatcher] as ClientClientDispatcher
  [ClientCoordinator] -down-> ClientCoordinatorAdapter
  [ClientConnector] -down-> ClientConnectorAdapter
  [ClientPersistence] -down--> ClientPersistenceAdapter
  [ClientClientDispatcher] --> [ClientConnector]
  [ClientClientDispatcher] --> [ClientCoordinator]
  client -down--> [ClientClientDispatcher]
  client -down--> [ClientPersistence]
}

frame "executor world" {
interface adapter as PersistenceAdapter
interface adapter as CoordinatorAdapter
interface adapter as ConnectorAdapter
[coordinator] -up--> CoordinatorAdapter
[connector] -up--> ConnectorAdapter
[persistence] -up-> PersistenceAdapter
[connector] <-- [client dispatcher]
[connector] <-- [executor dispatcher]
[executor] <-- [executor dispatcher]
[coordinator] <-- [client dispatcher]
[coordinator] <-- [executor dispatcher]
[persistence] <-- [executor]
}

database "Database" as Database
ClientPersistenceAdapter -down- Database
Database -down- PersistenceAdapter

node "Synchronization\nservice" as SyncService
ClientCoordinatorAdapter -down- SyncService
SyncService -down- CoordinatorAdapter

node "Message\nbus" as MessageBus
ClientConnectorAdapter -down- MessageBus
MessageBus -down- ConnectorAdapter

{% endplantuml %}

### Single-database model

Dynflow recognizes different expectations from the underlying
technologies from the persistence (durability), coordinator (real-time
synchronization) and connector (transport).

However, we also realize that for many use-cases, a single shared
database is just enough infrastructure the user needs for the job.
Forcing using different technologies would mean just useless overhead.

Therefore, it's possible to use a single shared SQL database to do
all the work.

{% plantuml %}

actor client

frame "client world" {
  interface adapter as ClientPersistenceAdapter
  interface adapter as ClientCoordinatorAdapter
  interface adapter as ClientConnectorAdapter
  component [coordinator] as ClientCoordinator
  component [persistence] as ClientPersistence
  component [connector] as ClientConnector
  component [client dispatcher] as ClientClientDispatcher
  [ClientCoordinator] -down-> ClientCoordinatorAdapter
  [ClientConnector] -down-> ClientConnectorAdapter
  [ClientPersistence] -down--> ClientPersistenceAdapter
  [ClientClientDispatcher] --> [ClientConnector]
  [ClientClientDispatcher] --> [ClientCoordinator]
  client -down--> [ClientClientDispatcher]
  client -down--> [ClientPersistence]
}

frame "executor world" {
interface adapter as PersistenceAdapter
interface adapter as CoordinatorAdapter
interface adapter as ConnectorAdapter
[coordinator] -up--> CoordinatorAdapter
[connector] -up--> ConnectorAdapter
[persistence] -up-> PersistenceAdapter
[connector] <-- [client dispatcher]
[connector] <-- [executor dispatcher]
[executor] <-- [executor dispatcher]
[coordinator] <-- [client dispatcher]
[coordinator] <-- [executor dispatcher]
[persistence] <-- [executor]
}

database "Database" as Database
ClientPersistenceAdapter -down- Database
Database -down- PersistenceAdapter

ClientCoordinatorAdapter -down- Database
Database -down- CoordinatorAdapter

ClientConnectorAdapter -down- Database
Database -down- ConnectorAdapter

{% endplantuml %}

{% info_block %}

Something as simple as sqlite is enough for getting the Dynlfow
up-and-running and getting something done.

For the best connector results, it's recommended to use PostgreSQL, as
Dynflow can utilize the
[listen/notify](http://www.postgresql.org/docs/9.0/static/sql-notify.html)
feature for better response times.

 {% endinfo_block %}

### Inner-world communication

{% plantuml %}
participant "Connector" as ClientConnector
participant "Connector" as ExecutorConnector

box "Client World"
  participant Client
  participant "Client Dispatcher"
  participant "ClientConnector"
end box

box "Executor World"
  participant "ExecutorConnector"
  participant "Executor Dispatcher"
  participant Executor
end box

autonumber
Client -> "Client Dispatcher" : publish_request\nexecution_plan_id
"Client Dispatcher" --> Client : IVar
"Client Dispatcher" -> "ClientConnector" : send\nEnvelope[Execution]
"ClientConnector" -> "ExecutorConnector" : handle_envelope\nEnvelope[Execution]
"ExecutorConnector" -> "Executor Dispatcher" : handle_request\nEnvelope[Execution]
"Executor Dispatcher" -> Executor : execute\nexecution_plan_id
note over Executor: executing…
activate Executor
"Executor Dispatcher" -> ExecutorConnector : send\nEnvelope[Accepted]
"ExecutorConnector" -> "ClientConnector" : handle_envelope\nEnvelope[Accepted]
"ClientConnector" -> "Client Dispatcher" : dispatch_response\nEnvelope[Accepted]
Executor -> "Executor Dispatcher" : finished
deactivate Executor
"Executor Dispatcher" -> ExecutorConnector : send\nEnvelope[Finished]
"ExecutorConnector" -> "ClientConnector" : handle_envelope\nEnvelope[Finished]
"ClientConnector" -> "Client Dispatcher" : dispatch_response\nEnvelope[Finished]
note over "Client Dispatcher": IVar fullfilled
{% endplantuml %}

1) the client prepares an execution plan, saves it into persistence
and passes its id to the client dispatcher

2) the client dispatcher creates an
[IVar](http://www.rubydoc.info/github/ruby-concurrency/concurrent-ruby/Concurrent/IVar)
that represents the future value of the execution plan after it
finishes execution. The client can use this value to wait for the
execution plan to finish or hook other procedures on the finish-time.

3) the client dispatcher creates an envelope (see
[connector](#connector) for more details), containing the request for
execution, with ``receiver id`` set to ``AnyExecutor``

4) the connector uses some scheduling algorithm to choose what executor to send the request to and
replaces the ``AnyExecutor`` with it. It sends the envelope the the
chosen executor.

5) the connector on the executor side receives the envelope and asks
the executor dispatcher to handle it

6) the executor dispatcher acquires the lock on the execution plan and
initiates the execution. In the mean-time, it lets the client know
that the work was accepted (there might be additional logic on the
client to handle a timeout after the work was not accepted)

7 - 9) the connector layer propagates the ``Accepted`` response back
to client

10) the executor finishes execution

11 - 12) the connector layer propagates the ``Finished`` response

13) the client dispatcher resolves the original ``IVar``, so that the
client is able to find out about the finished execution.

The behavior is the same even in the "one world" scenario: in that
case this world is participating both on the client and the executor
side, connected through a direct in-memory connector.

### Persistence

The persistence making sure that the serialized states of the
execution plans are persisted for recovery and status tracking. The
execution plan data are stored in it, with the actual state.

Unlike coordinator, all the persisted data don't have to be
available for all the worlds at the same time: every world needs just
the data that it is actively working on. Also, all the data don't have to
be fully synchronized between worlds (as long as the up-to-date data
about relevant execution plans are available for the world).

### Connector

Provides messages passing between worlds. The message has a form of
envelope of the following structure:

* **sender id** - the id of the world that produced the envelope
* **receiver id** - the id of the world that should receive the
    message, or ``AnyExecutor``, when load-balancing
* **request id** - the client-unique id used for pairing the
  request - response at the client
* **message** - the body of the message: the connector doesn't care
    about that as long as it's serializable

#### Load-balancing

The connector is responsible for spreading the load across the
executor worlds. It's determined by the ``AnyExecutor`` value at the
``request id`` field. The implementation available in the
current version uses a simple round-robin algorithm for this purpose.

### Coordinator

This component (especially important in a multi-executor setup): Makes
sure no two executors are executing the same execution plan at the
same time (a.k.a locking). It also provides the information
about the worlds available in the system (the worlds register). Unlike
the persistence, it's not required to persist the data (could be
recalculated), but it needs to provide a globally shared state.

The main type of objects the coordinator works with is a record which
consists of:

* type - the type of the record
* id - the id of the record (unique in scope of a type)
* data - data in arbitrary format, based on the type

There is a special type of record called ``lock``, that keeps the owner
information as well. It's used for keeping information about what
executor is actively working on what execution plan: the executor is
not allowed to start executing the unless it has successfully acquired
a lock for it.

### Thread-pools TODO

-   *how it works now*
-   *how it'll work*
-   *gotchas*
    -   *worker pool sizing*

### Suspending -> events TODO

## Use cases TODO

-   *Embedded without a DB, like inside CLI tool for a complex installation*
-   *reserve resources in planning do not try to do `if`s in run phase*
-   *Projects: katello, foreman, staypuft, fusor*

## Comments

**Comments are temporally turned on here for faster feedback.**
