# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "eventum/version"

Gem::Specification.new do |s|
  s.name        = "eventum"
  s.version     = Eventum::VERSION
  s.authors     = ["Ivan Necas"]
  s.email       = ["inecas@redhat.com"]
  s.homepage    = "http://github.com/iNecas/eventum"
  s.summary     = "Event based orchestration"
  s.description = "Modular reliable way for workflows processing"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ["lib"]

  s.add_dependency "activesupport"
  s.add_dependency "multi_json"
  s.add_dependency "apipie-params"
  s.add_development_dependency "minitest"
end
