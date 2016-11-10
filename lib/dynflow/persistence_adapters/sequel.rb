require 'sequel/no_core_ext' # to avoid sequel ~> 3.0 coliding with ActiveRecord
require 'multi_json'

module Dynflow
  module PersistenceAdapters

    Sequel.extension :migration

    class Sequel < Abstract
      include Algebrick::TypeCheck
      include Algebrick::Matching

      MAX_RETRIES = 10
      RETRY_DELAY = 1

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
                    action:              %w(caller_execution_plan_id caller_action_id),
                    step:                %w(state started_at ended_at real_time execution_time action_id progress_done progress_weight),
                    envelope:            %w(receiver_id),
                    coordinator_record:  %w(id owner_id class),
                    delayed:             %w(execution_plan_uuid start_at start_before args_serializer)}

      def initialize(config)
        config = config.dup
        @additional_responsibilities = { coordinator: true, connector: true }
        if config.is_a?(Hash) && config.key?(:additional_responsibilities)
          @additional_responsibilities.merge!(config.delete(:additional_responsibilities))
        end
        @db = initialize_db config
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
                          options[:filters])
        data_set.all.map { |record| load_data(record) }
      end

      def delete_execution_plans(filters, batch_size = 1000)
        count = 0
        filter(:execution_plan, table(:execution_plan), filters).each_slice(batch_size) do |plans|
          uuids = plans.map { |p| p.fetch(:uuid) }
          @db.transaction do
            table(:delayed).where(execution_plan_uuid: uuids).delete
            table(:step).where(execution_plan_uuid: uuids).delete
            table(:action).where(execution_plan_uuid: uuids).delete
            count += table(:execution_plan).where(uuid: uuids).delete
          end
        end
        return count
      end

      def load_execution_plan(execution_plan_id)
        load :execution_plan, uuid: execution_plan_id
      end

      def save_execution_plan(execution_plan_id, value)
        save :execution_plan, { uuid: execution_plan_id }, value
      end

      def delete_delayed_plans(filters, batch_size = 1000)
        count = 0
        filter(:delayed, table(:delayed), filters).each_slice(batch_size) do |plans|
          uuids = plans.map { |p| p.fetch(:execution_plan_uuid) }
          @db.transaction do
            count += table(:delayed).where(execution_plan_uuid: uuids).delete
          end
        end
        count
      end

      def find_past_delayed_plans(time)
        table(:delayed)
          .where('start_at <= ? OR (start_before IS NOT NULL AND start_before <= ?)', time, time)
          .order_by(:start_at)
          .all
          .map { |plan| load_data(plan) }
      end

      def load_delayed_plan(execution_plan_id)
        load :delayed, execution_plan_uuid: execution_plan_id
      rescue KeyError
        return nil
      end

      def save_delayed_plan(execution_plan_id, value)
        save :delayed, { execution_plan_uuid: execution_plan_id }, value
      end

      def load_step(execution_plan_id, step_id)
        load :step, execution_plan_uuid: execution_plan_id, id: step_id
      end

      def load_steps(execution_plan_id)
        load_records :step, execution_plan_uuid: execution_plan_id
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

      def connector_feature!
        unless @additional_responsibilities[:connector]
          raise "The sequel persistence adapter connector feature used but not enabled in additional_features"
        end
      end

      def save_envelope(data)
        connector_feature!
        save :envelope, {}, data
      end

      def pull_envelopes(receiver_id)
        connector_feature!
        db.transaction do
          data_set = table(:envelope).where(receiver_id: receiver_id).all
          envelopes = data_set.map { |record| load_data(record) }

          table(:envelope).where(id: data_set.map { |d| d[:id] }).delete
          return envelopes
        end
      end

      def push_envelope(envelope)
        connector_feature!
        table(:envelope).insert(prepare_record(:envelope, envelope))
      end

      def coordinator_feature!
        unless @additional_responsibilities[:coordinator]
          raise "The sequel persistence adapter coordinator feature used but not enabled in additional_features"
        end
      end

      def insert_coordinator_record(value)
        coordinator_feature!
        save :coordinator_record, {}, value
      end

      def update_coordinator_record(class_name, record_id, value)
        coordinator_feature!
        save :coordinator_record, {class: class_name, :id => record_id}, value
      end

      def delete_coordinator_record(class_name, record_id)
        coordinator_feature!
        table(:coordinator_record).where(class: class_name, id: record_id).delete
      end

      def find_coordinator_records(options)
        coordinator_feature!
        options = options.dup
        filters = (options[:filters] || {}).dup
        exclude_owner_id = filters.delete(:exclude_owner_id)
        data_set = filter(:coordinator_record, table(:coordinator_record), filters)
        if exclude_owner_id
          data_set = data_set.exclude(:owner_id => exclude_owner_id)
        end
        data_set.all.map { |record| load_data(record) }
      end

      def to_hash
        { execution_plans:      table(:execution_plan).all.to_a,
          steps:                table(:step).all.to_a,
          actions:              table(:action).all.to_a,
          envelopes:            table(:envelope).all.to_a }
      end

      private

      TABLES = { execution_plan:      :dynflow_execution_plans,
                 action:              :dynflow_actions,
                 step:                :dynflow_steps,
                 envelope:            :dynflow_envelopes,
                 coordinator_record:  :dynflow_coordinator_records,
                 delayed:             :dynflow_delayed_plans }

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
        existing_record = with_retry { table.first condition } unless condition.empty?

        if value
          record = prepare_record(what, value, (existing_record || condition))
          if existing_record
            with_retry { table.where(condition).update(record) }
          else
            with_retry { table.insert record }
          end

        else
          existing_record and with_retry { table.where(condition).delete }
        end
        value
      end

      def load_record(what, condition)
        table = table(what)
        if (record = with_retry { table.first(Utils.symbolize_keys(condition)) } )
          load_data(record)
        else
          raise KeyError, "searching: #{what} by: #{condition.inspect}"
        end
      end

      alias_method :load, :load_record

      def load_records(what, condition)
        table = table(what)
        records = with_retry { table.filter(Utils.symbolize_keys(condition)).all }
        records.map { |record| load_data(record) }
      end

      def load_data(record)
        Utils.indifferent_hash(MultiJson.load(record[:data]))
      end

      def delete(what, condition)
        table(what).where(Utils.symbolize_keys(condition)).delete
      end

      def extract_metadata(what, value)
        meta_keys = META_DATA.fetch(what)
        value     = Utils.indifferent_hash(value)
        meta_keys.inject({}) { |h, k| h.update k.to_sym => value[k] }
      end

      def dump_data(value)
        MultiJson.dump Type!(value, Hash)
      end

      def paginate(data_set, options)
        page     = Integer(options[:page]) if options[:page]
        per_page = Integer(options[:per_page]) if options[:per_page]

        if page
          raise ArgumentError, "page specified without per_page attribute" unless per_page
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

      def filter(what, data_set, filters)
        Type! filters, NilClass, Hash
        return data_set if filters.nil?

        unknown = filters.keys.map(&:to_s) - META_DATA.fetch(what)
        if what == :execution_plan
          unknown -= %w[uuid caller_execution_plan_id caller_action_id]

          if filters.key?('caller_action_id') && !filters.key?('caller_execution_plan_id')
            raise ArgumentError, "caller_action_id given but caller_execution_plan_id missing"
          end

          if filters.key?('caller_execution_plan_id')
            data_set = data_set.join_table(:inner, TABLES[:action], :execution_plan_uuid => :uuid).
                select_all(TABLES[:execution_plan]).distinct
          end
        end

        unless unknown.empty?
          raise ArgumentError, "unkown columns: #{unknown.inspect}"
        end

        data_set.where Utils.symbolize_keys(filters)
      end

      def with_retry
        attempts = 0
        begin
          yield
        rescue ::Sequel::UniqueConstraintViolation => e
          raise e
        rescue Exception => e
          attempts += 1
          log(:error, e)
          if attempts > MAX_RETRIES
            log(:error, "The number of MAX_RETRIES exceeded")
            raise Errors::PersistenceError.delegate(e)
          else
            log(:error, "Persistence retry no. #{attempts}")
            sleep RETRY_DELAY
            retry
          end
        end
      end
    end
  end
end
