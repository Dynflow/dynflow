module Dynflow
  module Executors

    require 'dynflow/executors/abstract'
    require 'dynflow/executors/parallel'

    # Every time we run a code that can be defined outside of Dynflow,
    # we should wrap it with this method, and we can ensure here to do
    # necessary cleanup, such as cleaning ActiveRecord connections
    def self.run_user_code
      yield
    ensure
      ::ActiveRecord::Base.clear_active_connections! if defined? ::ActiveRecord
    end

  end
end
