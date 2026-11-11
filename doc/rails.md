# Using Dynflow with Rails

Dynflow can use the Rails application's Active Record database and can run its
executor either inside the Rails process or in a separate process. The example
below uses `app/actions` for action classes.

## Install the gems

Add Dynflow and its Rails runtime dependency to the `Gemfile`:

```ruby
gem 'dynflow', '~> 2.0'
gem 'get_process_mem'
```

Then run `bundle install`.

Dynflow uses the current Rails environment from `config/database.yml`. With
PostgreSQL, Dynflow creates its tables in the configured database. With SQLite,
it creates a separate database next to the application database, prefixed with
`dynflow-`.

## Configure the Rails application

Create `config/initializers/dynflow.rb`:

```ruby
runtime = Dynflow::Rails.new
runtime.require!
runtime.executor! if ENV['DYNFLOW_EXECUTOR'] == 'true'
runtime.config.eager_load_paths << Rails.root.join('app/actions')

Rails.application.define_singleton_method(:dynflow) { runtime }

Rails.application.config.after_initialize do
  Rails.application.dynflow.eager_load_actions!
  Rails.application.dynflow.initialize!
end
```

Dynflow runs an in-process executor by default in development and test. In
production, it defaults to a client-only world and expects a separate executor.
For a single-process production deployment, set `runtime.config.remote = false`
in the initializer instead.

To use Dynflow as the Active Job adapter, also add this to
`config/application.rb`:

```ruby
config.active_job.queue_adapter = :dynflow
```

## Define and run an action

Create `app/actions/hello_world.rb`:

```ruby
class HelloWorld < Dynflow::Action
  def plan(who)
    plan_self(who: who)
  end

  def run
    Rails.logger.info("Hello #{input[:who]}")
  end
end
```

The action can then be triggered from application code or the Rails console:

```ruby
triggered = Rails.application.dynflow.world.trigger(HelloWorld, 'my friend')
triggered.finished.wait
```

`trigger` returns immediately with a `Dynflow::World::Triggered` handle. Waiting
on `finished` is useful in a console or test, but request-handling code will
normally keep the execution asynchronous.

## Run a separate production executor

When the web processes use the default production setting (`remote = true`),
start at least one process with `DYNFLOW_EXECUTOR=true`. For example, create
`bin/dynflow-executor`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

ENV['DYNFLOW_EXECUTOR'] = 'true'
require_relative '../config/environment'

sleep
```

Run it under the same process supervisor as the Rails application:

```console
bundle exec ruby bin/dynflow-executor
```

The web and executor processes must use the same database. PostgreSQL is
recommended for a multi-process deployment. Action classes must be available
to both process types.

## Common configuration

Configure the runtime before the `after_initialize` block runs:

```ruby
runtime.config.pool_size = 5
runtime.config.queues.add(:slow, pool_size: 2)
runtime.config.on_init do |world|
  Rails.logger.info("Dynflow world #{world.id} started")
end
```

The Active Record connection pool is increased automatically when necessary to
cover Dynflow's worker threads. Ensure the database server itself has enough
connections for every Rails and executor process.
