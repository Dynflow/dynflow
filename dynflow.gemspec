# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "dynflow/version"

Gem::Specification.new do |s|
  s.name        = "dynflow"
  s.version     = Dynflow::VERSION
  s.authors     = ["Ivan Necas"]
  s.email       = ["inecas@redhat.com"]
  s.homepage    = "http://github.com/Dynflow/dynflow"
  s.summary     = "DYNamic workFLOW engine"
  s.description = "Generate and executed workflows dynamically based "+
      "on input data and leave it open for others to jump into it as well"
  s.license     = "MIT"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ["lib"]

  s.required_ruby_version = '>= 1.9.3'

  s.add_dependency "activesupport"
  s.add_dependency "multi_json"
  s.add_dependency "apipie-params"
  s.add_dependency "algebrick", '~> 0.5.0'
  s.add_dependency "concurrent-ruby", '~> 0.8.0'

  s.add_development_dependency "rack-test"
  s.add_development_dependency "minitest"
  s.add_development_dependency "minitest-reporters"
  s.add_development_dependency "activerecord"
  s.add_development_dependency "sequel"
  s.add_development_dependency "sqlite3"
  s.add_development_dependency "pg"
  s.add_development_dependency "sinatra"
end
