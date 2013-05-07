require 'rake/testtask'
require 'fileutils'

desc "Generic tests"
Rake::TestTask.new do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/*_test.rb']
  t.verbose = true
end

namespace :test do
  desc "All tests"
  task :all => [:test] do
  end
end
