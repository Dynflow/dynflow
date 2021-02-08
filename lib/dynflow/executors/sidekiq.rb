module Dynflow
  module Executors
    module Sidekiq
      loader = Zeitwerk::Loader.new
      loader.push_dir("#{__dir__}/sidekiq", namespace: ::Dynflow::Executors::Sidekiq)
      loader.log!
      loader.setup
      loader.eager_load
    end
  end
end
