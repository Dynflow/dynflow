require 'apipie-params'
require 'active_support/core_ext/hash/indifferent_access'
require 'dynflow/logger'
require 'dynflow/execution_plan'
require 'dynflow/dispatcher'
require 'dynflow/executor'
require 'dynflow/bus'
require 'dynflow/action'

files = Dir[File.dirname(__FILE__) + '/dynflow/execution/step.rb']
files += Dir[File.dirname(__FILE__) + '/dynflow/execution/*.rb']

files.uniq.each{ |file| require file }

module Dynflow

  ROOT_PATH = File.expand_path('../..', __FILE__)

end
