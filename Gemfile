# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :concurrent_ruby_ext, optional: ENV.key?('CI') && ENV['CONCURRENT_RUBY_EXT'] != 'true' do
  gem 'concurrent-ruby-ext', '~> 1.1.3'
end

group :pry, optional: ENV.key?('CI') do
  gem 'pry'
  gem 'pry-byebug'
end

group :sidekiq do
  gem 'gitlab-sidekiq-fetcher', :require => 'sidekiq-reliable-fetch'
  gem 'sidekiq'
end

group :postgresql, optional: ENV.key?('CI') && ENV['DB'] != 'postgresql' do
  gem "pg"
end

group :mysql, optional: ENV.key?('CI') && ENV['DB'] != 'mysql' do
  gem "mysql2"
end

group :lint do
  gem 'theforeman-rubocop', '~> 0.0.4'
end

group :memory_watcher do
  gem 'get_process_mem'
end

group :rails do
  gem 'daemons'
  gem 'logging'
  gem 'rails', '>= 4.2.9', '< 7'
end

group :telemetry do
  gem 'statsd-instrument'
end
