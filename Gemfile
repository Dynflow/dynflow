source 'https://rubygems.org'

gemspec

group :concurrent_ruby_ext do
  gem 'concurrent-ruby-ext', '~> 1.1.3'
end

group :pry do
  gem 'pry'
  gem 'pry-byebug'
end

group :sidekiq do
  gem 'sidekiq'
  gem 'gitlab-sidekiq-fetcher', :require => 'sidekiq-reliable-fetch'
end

group :postgresql do
  gem "pg"
end

group :mysql do
  gem "mysql2"
end

group :lint do
  gem 'rubocop', '0.39.0'
end

group :memory_watcher do
  gem 'get_process_mem'
end

group :rails do
  gem 'daemons'
  gem 'rails', '>= 4.2.9'
  gem 'logging'
end

group :telemetry do
  gem 'statsd-instrument'
end
