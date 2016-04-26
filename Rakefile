require 'rake/testtask'
require 'fileutils'

Rake::TestTask.new do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/*_test.rb']
  t.verbose = true
  t.warning = false
end

desc Rake::Task['test'].comment
task :default => :test
