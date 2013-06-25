require 'logger'

module Dynflow
  module Persistence
    class ActiveRecordDriver

      def initialize
        require 'dynflow/persistence/active_record/persisted_plan'
        require 'dynflow/persistence/active_record/persisted_step'
      end

      def persistence_class
        Dynflow::Persistence::ActiveRecord::PersistedPlan
      end

      def self.migrations_path
        File.expand_path('../../../db/migrate', __FILE__)
      end

      def self.bootstrap_migrations(app)
        app.config.paths['db/migrate'] << self.migrations_path
      end



    end



    class ActiveRecordTransaction
      class << self

        def transaction(&block)
          ActiveRecord::Base.transaction(&block)
        end

        def rollback
          raise ActiveRecord::Rollback
        end

      end
    end


  end
end


