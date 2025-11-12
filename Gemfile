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

group :lint do
  gem 'theforeman-rubocop', '~> 0.0.4'
end

group :memory_watcher do
  gem 'get_process_mem'
end

group :rails do
  gem 'daemons'
  gem 'logging'
  gem 'rails', '>= 7', '< 8'
end

group :telemetry do
  gem 'statsd-instrument'
end

local_gemfile = File.join(File.dirname(__FILE__), 'Gemfile.local.rb')
self.instance_eval(Bundler.read_file(local_gemfile)) if File.exist?(local_gemfile)
