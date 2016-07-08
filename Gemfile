source 'https://rubygems.org'

gemspec

group :concurrent_ruby_ext do
  gem 'concurrent-ruby-ext', '~> 1.0'
end

group :pry do
  gem 'pry'
end

group :postgresql do
  gem "pg"
end

group :mysql do
  gem "mysql2"
end

if RUBY_VERSION < "2.2.2"
  gem 'activesupport', '~> 4.2'
end
