require 'dynflow'
require 'rake/testtask'
require 'fileutils'

Rake::TestTask.new do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/*_test.rb']
  t.verbose = true
  t.warning = false
end

namespace :foreman_tasks do
  desc "Export tasks"

  task :export_tasks do
    export_task = Dynflow::Tasks::Export.new do |t|
      config = ::Dynflow::Config.new.tap do |config|
        config.logger_adapter      = ::Dynflow::LoggerAdapters::Simple.new $stdout, 2
        config.pool_size           = 5
        config.persistence_adapter = ::Dynflow::PersistenceAdapters::Sequel.new ENV['DB_CONN_STRING']
        config.executor            = false
        config.connector           = Proc.new { |world| Dynflow::Connectors::Database.new(world) }
        config.auto_execute        = false
      end
      t.world  = ::Dynflow::World.new(config)
    end
    Rake::Task[export_task.name].invoke
  end
end

desc Rake::Task['test'].comment
task :default => :test
