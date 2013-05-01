require 'rake/testtask'
require 'fileutils'

desc "Generic tests"
Rake::TestTask.new do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/*_test.rb']
  t.verbose = true
end

desc "Rails specific tests"
Rake::TestTask.new('test:rails') do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/rails/*_test.rb']
  t.verbose = true
end

TEST_DUMMY_DIR = File.expand_path('../test/dummy', __FILE__)

namespace :test do
  desc "All tests"
  task :all => [:test, :'test:rails'] do
  end

  task :db_prepare do
    FileUtils.cd(TEST_DUMMY_DIR) do
      puts "Dropping database"
      system('rake db:drop RAILS_ENV=test')
      puts "(re)installing engine migrations"
      Dir['db/migrate/*.dynflow.rb'].each do |f|
        puts "Removing #{f}"
        FileUtils.rm(f)
      end
      system('rake railties:install:migrations')
      puts "Migrating database"
      system('rake db:migrate db:schema:dump db:test:prepare RAILS_ENV=test') || fail
    end
  end
end
