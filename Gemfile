source 'https://rubygems.org'

gemspec

group :concurrent_ruby_ext do
  gem 'concurrent-ruby-ext', '= 1.0.3'
end

group :pry do
  gem 'pry'
  gem 'pry-byebug'
end

group :postgresql do
  if RUBY_VERSION <= '2'
    gem 'pg', '< 0.19'
  else
    gem "pg"
  end
end

group :mysql do
  gem "mysql2"
end

if RUBY_VERSION < "2.2.2"
  gem 'activesupport', '~> 4.2'
  gem 'sinatra', '~> 1.4.8'
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
