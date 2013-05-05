require 'active_support/core_ext/hash/indifferent_access'
require 'dynflow/logger'
require 'dynflow/execution_plan'
require 'dynflow/dispatcher'
require 'dynflow/bus'
require 'dynflow/step'
require 'dynflow/action'

if defined? ::Rails::Engine
  require 'jquery-rails'
  require 'dynflow/engine'
end

module Dynflow

end
