# -*- encoding: utf-8 -*-
# frozen_string_literal: true

$:.push File.expand_path("../lib", __FILE__)
require "dynflow/version"

Gem::Specification.new do |s|
  s.name        = "dynflow"
  s.version     = Dynflow::VERSION
  s.authors     = ["Ivan Necas", "Petr Chalupa"]
  s.email       = ["inecas@redhat.com"]
  s.homepage    = "https://github.com/Dynflow/dynflow"
  s.summary     = "DYNamic workFLOW engine"
  s.description = "Ruby workflow/orchestration engine"
  s.license     = "MIT"

  s.files         = `git ls-files`.split("\n").reject { |file| file == '.packit.yaml' }
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ["lib"]

  s.required_ruby_version = '>= 3.0.0'

  s.add_dependency "algebrick", '~> 0.7.0'
  s.add_dependency "concurrent-ruby", '~> 1.1.3'
  s.add_dependency "concurrent-ruby-edge", '~> 0.6.0'
  s.add_dependency "csv", "~> 3.1"
  s.add_dependency "msgpack", '~> 1.3', '>= 1.3.3'
  s.add_dependency "multi_json"
  s.add_dependency "sequel", '>= 4.0.0'

  s.add_development_dependency 'activejob'
  s.add_development_dependency "activerecord"
  s.add_development_dependency 'drb' # ActiveSupport requires this, but doesn't explicitly depend on it
  s.add_development_dependency "minitest", "< 5.19"
  s.add_development_dependency "minitest-reporters"
  s.add_development_dependency "minitest-stub-const"
  s.add_development_dependency 'mocha'
  s.add_development_dependency 'mutex_m' # Rails require this, but don't explicitly depend on it
  s.add_development_dependency 'ostruct'
  s.add_development_dependency "rack-test"
  s.add_development_dependency "rake"
  s.add_development_dependency "sinatra"
  s.add_development_dependency "sqlite3"
  s.add_development_dependency 'syslog' # logging requires this, but doesn't explicitly depend on it
end
