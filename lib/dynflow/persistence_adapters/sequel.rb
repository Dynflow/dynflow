require 'sequel/no_core_ext' # to avoid sequel ~> 3.0 coliding with ActiveRecord
require 'multi_json'

module Dynflow
  module PersistenceAdapters

    Sequel.extension :migration

    class Sequel < Abstract
      include Algebrick::TypeCheck
      include Algebrick::Matching

      attr_reader :db

      def pagination?
        true
      end

      def filtering_by
        META_DATA.fetch :execution_plan
      end

      def ordering_by
        META_DATA.fetch :execution_plan
      end

      META_DATA = { execution_plan:      %w(state result started_at ended_at real_time execution_time),
                    action:              [],
                    step:                %w(state started_at ended_at real_time execution_time action_id progress_done progress_weight),
                    world:               %w(id executor),
                    envelope:            %w(receiver_id),
                    executor_allocation: %w(world_id execution_plan_id) }

      def initialize(db_path)
        @db = initialize_db db_path
        migrate_db
      end

      def transaction(&block)
        db.transaction(&block)
      end

      def find_execution_plans(options = {})
        options[:order_by] ||= :started_at
        data_set = filter(:execution_plan,
                          order(:execution_plan,
                                paginate(table(:execution_plan), options),
                                options),
                          options)

        data_set.map do |record|
          HashWithIndifferentAccess.new(MultiJson.load(record[:data]))
        end
      end

      def load_execution_plan(execution_plan_id)
        load :execution_plan, uuid: execution_plan_id
      end

      def save_execution_plan(execution_plan_id, value)
        save :execution_plan, { uuid: execution_plan_id }, value
      end

      def load_step(execution_plan_id, step_id)
        load :step, execution_plan_uuid: execution_plan_id, id: step_id
      end

      def save_step(execution_plan_id, step_id, value)
        save :step, { execution_plan_uuid: execution_plan_id, id: step_id }, value
      end

      def load_action(execution_plan_id, action_id)
        load :action, execution_plan_uuid: execution_plan_id, id: action_id
      end

      def save_action(execution_plan_id, action_id, value)
        save :action, { execution_plan_uuid: execution_plan_id, id: action_id }, value
      end

      def find_worlds(options)
        data_set = filter(:world,
                          order(:world,
                                paginate(table(:world),
                                         options),
                                options),
                          options)

        data_set.map do |record|
          Persistence::RegisteredWorld[record]
        end
      end

      def save_world(id, value)
        save :world, { id: id }, value
      end

      def delete_world(id)
        delete :world, { id: id }
      end

      def save_executor_allocation(executor_allocation)
        conditions = { world_id: executor_allocation.world_id,
                       execution_plan_id: executor_allocation.execution_plan_id }
        save :executor_allocation, conditions, executor_allocation
      end

      def find_executor_allocations(options)
        options = options.dup
        data_set = filter(:executor_allocation,
                          order(:executor_allocation,
                                paginate(table(:executor_allocation), options),
                                options),
                          options)


        data_set.map do |record|
          Persistence::ExecutorAllocation[record]
        end
      end

      def delete_executor_allocations(options)
        delete :executor_allocation, options
      end

      def save_envelope(data)
        save :envelope, {}, data
      end

      def pull_envelopes(receiver_id)
        db.transaction do
          data_set = table(:envelope).where(receiver_id: receiver_id).to_a

          envelopes = data_set.map do |record|
            Serializable::AlgebrickSerializer.instance.load(record[:data], Dispatcher::Envelope)
          end

          table(:envelope).where(id: data_set.map { |d| d[:id] }).delete
          return envelopes
        end
      end

      def push_envelope(envelope)
        table(:envelope).insert(prepare_record(:envelope, envelope))
      end

      def to_hash
        { execution_plans:      table(:execution_plan).all,
          steps:                table(:step).all,
          actions:              table(:action).all,
          worlds:               table(:world).all,
          envelopes:            table(:envelope).all,
          executor_allocations: table(:executor_allocation).all}
      end

      private

      TABLES = { execution_plan:      :dynflow_execution_plans,
                 action:              :dynflow_actions,
                 step:                :dynflow_steps,
                 world:               :dynflow_worlds,
                 envelope:            :dynflow_envelopes,
                 executor_allocation: :dynflow_executor_allocations }

      def table(which)
        db[TABLES.fetch(which)]
      end

      def initialize_db(db_path)
        ::Sequel.connect db_path
      end

      def self.migrations_path
        File.expand_path('../sequel_migrations', __FILE__)
      end

      def migrate_db
        ::Sequel::Migrator.run(db, self.class.migrations_path, table: 'dynflow_schema_info')
      end

      def prepare_record(table_name, value, base = {})
        record = base.dup
        if table(table_name).columns.include?(:data)
          record[:data] = dump_data(value)
        end
        record.merge! extract_metadata(table_name, value)
        record.each { |k, v| record[k] = v.to_s if v.is_a? Symbol }
        record
      end

      def save(what, condition, value)
        table           = table(what)
        existing_record = table.first condition unless condition.empty?

        if value
          record = prepare_record(what, value, (existing_record || condition))
          if existing_record
            table.where(condition).update(record)
          else
            table.insert record
          end

        else
          existing_record and table.where(condition).delete
        end
        value
      end

      def load(what, condition)
        table = table(what)
        if (record = table.first(condition.symbolize_keys))
          HashWithIndifferentAccess.new MultiJson.load(record[:data])
        else
          raise KeyError, "searching: #{what} by: #{condition.inspect}"
        end
      end

      def delete(what, condition)
        table(what).where(condition.symbolize_keys).delete
      end

      def extract_metadata(what, value)
        meta_keys = META_DATA.fetch(what)
        match value,
              (on Hash do
                 value         = value.with_indifferent_access
                 meta_keys.inject({}) { |h, k| h.update k.to_sym => value.fetch(k) }
               end),
              (on Algebrick::Value do
                 meta_keys.inject({}) { |h, k| h.update k.to_sym => value[k.to_sym] }
               end)
      end

      def dump_data(value)
        match value,
              (on Hash do
                 MultiJson.dump Type!(value, Hash)
               end),
              (on Algebrick::Value do
                 Serializable::AlgebrickSerializer.instance.dump(value)
               end)
      end

      def paginate(data_set, options)
        page     = Integer(options[:page] || 0)
        per_page = Integer(options[:per_page] || 20)

        if page
          data_set.limit per_page, per_page * page
        else
          data_set
        end
      end

      def order(what, data_set, options)
        order_by = (options[:order_by]).to_s
        return data_set if order_by.empty?
        unless META_DATA.fetch(what).include? order_by
          raise ArgumentError, "unknown column #{order_by.inspect}"
        end
        order_by = order_by.to_sym
        data_set.order_by options[:desc] ? ::Sequel.desc(order_by) : order_by
      end

      def filter(what, data_set, options)
        filters = Type! options[:filters], NilClass, Hash
        return data_set if filters.nil?

        unless (unknown = filters.keys.map(&:to_s) - META_DATA.fetch(what)).empty?
          raise ArgumentError, "unkown columns: #{unknown.inspect}"
        end

        data_set.where filters.symbolize_keys
      end
    end
  end
end
