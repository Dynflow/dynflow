# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "dynflow/version"

Gem::Specification.new do |s|
  s.name        = "dynflow"
  s.version     = Dynflow::VERSION
  s.authors     = ["Ivan Necas", "Petr Chalupa"]
  s.email       = ["inecas@redhat.com"]
  s.homepage    = "http://github.com/Dynflow/dynflow"
  s.summary     = "DYNamic workFLOW engine"
  s.description = "Ruby workflow/orchestration engine"
  s.license     = "MIT"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ["lib"]

  s.required_ruby_version = '>= 2.0.0'

  s.add_dependency "multi_json"
  s.add_dependency "apipie-params"
  s.add_dependency "algebrick", '~> 0.7.0'
  s.add_dependency "concurrent-ruby", '~> 1.0'
  s.add_dependency "concurrent-ruby-edge", '~> 0.2.0'
  s.add_dependency "sequel", '>= 4.0.0'

  s.add_development_dependency "rake"
  s.add_development_dependency "rack-test"
  s.add_development_dependency "minitest"
  s.add_development_dependency "minitest-reporters"
  s.add_development_dependency "activerecord", '< 5.0.0'
  s.add_development_dependency 'activejob', '< 5.0.0'
  s.add_development_dependency "sqlite3"
  s.add_development_dependency "sinatra"
  s.add_development_dependency 'mocha'
end
