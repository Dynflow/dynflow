# frozen_string_literal: true

require 'sequel'
require 'msgpack'
require 'fileutils'
require 'csv'

# rubocop:disable Metrics/ClassLength
module Dynflow
  module PersistenceAdapters
    Sequel.extension :migration
    Sequel.database_timezone = :utc

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

      META_DATA = { execution_plan:      %w(label state result started_at ended_at real_time execution_time root_plan_step_id class),
                    action:              %w(caller_execution_plan_id caller_action_id class plan_step_id run_step_id finalize_step_id),
                    step:                %w(state started_at ended_at real_time execution_time action_id progress_done progress_weight
                                            class action_class execution_plan_uuid queue),
                    envelope:            %w(receiver_id),
                    coordinator_record:  %w(id owner_id class),
                    delayed:             %w(execution_plan_uuid start_at start_before args_serializer frozen),
                    output_chunk:        %w(execution_plan_uuid action_id kind timestamp) }

      SERIALIZABLE_COLUMNS = { action:  %w(input output),
                               delayed: %w(serialized_args),
                               execution_plan: %w(run_flow finalize_flow execution_history step_ids),
                               step:    %w(error children),
                               output_chunk: %w(chunk) }

      def initialize(config)
        migrate = true
        config = config.dup
        @additional_responsibilities = { coordinator: true, connector: true }
        if config.is_a?(Hash)
          @additional_responsibilities.merge!(config.delete(:additional_responsibilities)) if config.key?(:additional_responsibilities)
          migrate = config.fetch(:migrate, true)
        end
        @db = initialize_db config
        migrate_db if migrate
      end

      def transaction(&block)
        db.transaction(&block)
      end

      def find_execution_plans(options = {})
        table_name = :execution_plan
        options[:order_by] ||= :started_at
        data_set = filter(table_name,
          order(table_name,
            paginate(table(table_name), options),
            options),
          options[:filters])
        data_set.all.map { |record| execution_plan_column_map(load_data(record, table_name)) }
      end

      def find_execution_plan_counts(options = {})
        filter(:execution_plan, table(:execution_plan), options[:filters]).count
      end

      def find_execution_plan_counts_after(timestamp, options = {})
        filter(:execution_plan, table(:execution_plan), options[:filters]).filter(::Sequel.lit('ended_at >= ?', timestamp)).count
      end

      def find_execution_plan_statuses(options)
        plans = filter(:execution_plan, table(:execution_plan), options[:filters])
                .select(:uuid, :state, :result)

        plans.each_with_object({}) do |current, acc|
          uuid = current.delete(:uuid)
          acc[uuid] = current
        end
      end

      def delete_execution_plans(filters, batch_size = 1000, backup_dir = nil)
        count = 0
        filter(:execution_plan, table(:execution_plan), filters).each_slice(batch_size) do |plans|
          uuids = plans.map { |p| p.fetch(:uuid) }
          @db.transaction do
            table(:delayed).where(execution_plan_uuid: uuids).delete

            steps = table(:step).where(execution_plan_uuid: uuids)
            backup_to_csv(:step, steps, backup_dir, 'steps.csv') if backup_dir
            steps.delete

            table(:output_chunk).where(execution_plan_uuid: uuids).delete

            actions = table(:action).where(execution_plan_uuid: uuids)
            backup_to_csv(:action, actions, backup_dir, 'actions.csv') if backup_dir
            actions.delete

            execution_plans = table(:execution_plan).where(uuid: uuids)
            backup_to_csv(:execution_plan, execution_plans, backup_dir, 'execution_plans.csv') if backup_dir
            count += execution_plans.delete
          end
        end
        return count
      end

      def load_execution_plan(execution_plan_id)
        execution_plan_column_map(load :execution_plan, uuid: execution_plan_id)
      end

      def save_execution_plan(execution_plan_id, value)
        save :execution_plan, { uuid: execution_plan_id }, value, with_data: false
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

      def find_old_execution_plans(age)
        table_name = :execution_plan
        table(table_name)
          .where(::Sequel.lit('ended_at <= ? AND state = ?', age, 'stopped'))
          .all.map { |plan| execution_plan_column_map(load_data plan, table_name) }
      end

      def find_past_delayed_plans(time)
        table_name = :delayed
        table(table_name)
          .where(::Sequel.lit('start_at <= ? OR (start_before IS NOT NULL AND start_before <= ?)', time, time))
          .where(:frozen => false)
          .order_by(:start_at)
          .all
          .map { |plan| load_data(plan, table_name) }
      end

      def load_delayed_plan(execution_plan_id)
        load :delayed, execution_plan_uuid: execution_plan_id
      rescue KeyError
        return nil
      end

      def save_delayed_plan(execution_plan_id, value)
        save :delayed, { execution_plan_uuid: execution_plan_id }, value, with_data: false
      end

      def load_step(execution_plan_id, step_id)
        load :step, execution_plan_uuid: execution_plan_id, id: step_id
      end

      def load_steps(execution_plan_id)
        load_records :step, execution_plan_uuid: execution_plan_id
      end

      def save_step(execution_plan_id, step_id, value, update_conditions = {})
        save :step, { execution_plan_uuid: execution_plan_id, id: step_id }, value,
          with_data: false, update_conditions: update_conditions
      end

      def load_action(execution_plan_id, action_id)
        load :action, execution_plan_uuid: execution_plan_id, id: action_id
      end

      def load_actions(execution_plan_id, action_ids)
        load_records :action, { execution_plan_uuid: execution_plan_id, id: action_ids }
      end

      def load_actions_attributes(execution_plan_id, attributes)
        load_records :action, { execution_plan_uuid: execution_plan_id }, attributes
      end

      def save_action(execution_plan_id, action_id, value)
        save :action, { execution_plan_uuid: execution_plan_id, id: action_id }, value, with_data: false
      end

      def save_output_chunks(execution_plan_id, action_id, chunks)
        chunks.each do |chunk|
          chunk[:execution_plan_uuid] = execution_plan_id
          chunk[:action_id] = action_id
          save :output_chunk, {}, chunk, with_data: false
        end
      end

      def load_output_chunks(execution_plan_id, action_id)
        load_records :output_chunk, { execution_plan_uuid: execution_plan_id, action_id: action_id }, [:timestamp, :kind, :chunk]
      end

      def delete_output_chunks(execution_plan_id, action_id)
        filter(:output_chunk, table(:output_chunk), { execution_plan_uuid: execution_plan_id, action_id: action_id }).delete
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

      def prune_envelopes(receiver_ids)
        connector_feature!
        table(:envelope).where(receiver_id: receiver_ids).delete
      end

      def prune_undeliverable_envelopes
        connector_feature!
        table(:envelope).where(receiver_id: table(:coordinator_record).select(:id)).invert.delete
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
        save :coordinator_record, { class: class_name, :id => record_id }, value
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

      def migrate_db
        ::Sequel::Migrator.run(db, self.class.migrations_path, table: 'dynflow_schema_info')
      end

      def abort_if_pending_migrations!
        ::Sequel::Migrator.check_current(db, self.class.migrations_path, table: 'dynflow_schema_info')
      end

      private

      TABLES = { execution_plan:      :dynflow_execution_plans,
                 action:              :dynflow_actions,
                 step:                :dynflow_steps,
                 envelope:            :dynflow_envelopes,
                 coordinator_record:  :dynflow_coordinator_records,
                 delayed:             :dynflow_delayed_plans,
                 output_chunk:        :dynflow_output_chunks }

      def table(which)
        db[TABLES.fetch(which)]
      end

      def initialize_db(db_path)
        logger = Logger.new($stderr) if ENV['DYNFLOW_SQL_LOG']
        ::Sequel.connect db_path, logger: logger
      end

      def self.migrations_path
        File.expand_path('../sequel_migrations', __FILE__)
      end

      def prepare_record(table_name, value, base = {}, with_data = true)
        record = base.dup
        has_data_column = table(table_name).columns.include?(:data)
        if with_data && has_data_column
          record[:data] = dump_data(value)
        else
          if has_data_column
            record[:data] = nil
          else
            record.delete(:data)
          end
          record.merge! serialize_columns(table_name, value)
        end

        record.merge! extract_metadata(table_name, value)
        record.each { |k, v| record[k] = v.to_s if v.is_a? Symbol }

        record
      end

      def serialize_columns(table_name, record)
        record.reduce({}) do |acc, (key, value)|
          if SERIALIZABLE_COLUMNS.fetch(table_name, []).include?(key.to_s)
            acc.merge(key.to_sym => dump_data(value))
          else
            acc
          end
        end
      end

      def save(what, condition, value, with_data: true, update_conditions: {})
        table           = table(what)
        existing_record = with_retry { table.first condition } unless condition.empty?

        if value
          record = prepare_record(what, value, (existing_record || condition), with_data)
          if existing_record
            record = prune_unchanged(what, existing_record, record)
            return value if record.empty?
            condition = update_conditions.merge(condition)
            return with_retry { table.where(condition).update(record) }
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
        if (record = with_retry { table.first(Utils.symbolize_keys(condition)) })
          load_data(record, what)
        else
          raise KeyError, "searching: #{what} by: #{condition.inspect}"
        end
      end

      def prune_unchanged(what, object, record)
        record = record.dup
        table(what).columns.each do |column|
          record.delete(column) if object[column] == record[column]
        end
        record
      end

      alias_method :load, :load_record

      def load_records(what, condition, keys = nil)
        table = table(what)
        records = with_retry do
          filtered = table.filter(Utils.symbolize_keys(condition))
          # Filter out requested columns which the table doesn't have, load data just in case
          unless keys.nil?
            columns = table.columns & keys
            columns |= [:data] if table.columns.include?(:data)
            filtered = filtered.select(*columns)
          end
          filtered.all
        end
        records = records.map { |record| load_data(record, what) }
        return records if keys.nil?
        records.map do |record|
          keys.reduce({}) do |acc, key|
            acc.merge(key => record[key])
          end
        end
      end

      def load_data(record, what = nil)
        hash = if record[:data].nil?
                 SERIALIZABLE_COLUMNS.fetch(what, []).each do |key|
                   key = key.to_sym
                   record[key] = MessagePack.unpack(record[key].to_s) unless record[key].nil?
                 end
                 record
               else
                 MessagePack.unpack(record[:data].to_s)
               end
        Utils.indifferent_hash(hash)
      end

      def ensure_backup_dir(backup_dir)
        FileUtils.mkdir_p(backup_dir) unless File.directory?(backup_dir)
      end

      def backup_to_csv(table_name, dataset, backup_dir, file_name)
        ensure_backup_dir(backup_dir)
        csv_file = File.join(backup_dir, file_name)
        appending = File.exist?(csv_file)
        columns = dataset.columns
        File.open(csv_file, 'a') do |csv|
          csv << columns.to_csv unless appending
          dataset.each do |row|
            values = columns.map do |col|
              value = row[col]
              value = value.unpack('H*').first if value && SERIALIZABLE_COLUMNS.fetch(table_name, []).include?(col.to_s)
              value
            end
            csv << values.to_csv
          end
        end
        dataset
      end

      def delete(what, condition)
        table(what).where(Utils.symbolize_keys(condition)).delete
      end

      def extract_metadata(what, value)
        meta_keys = META_DATA.fetch(what) - SERIALIZABLE_COLUMNS.fetch(what, [])
        value     = Utils.indifferent_hash(value)
        meta_keys.inject({}) { |h, k| h.update k.to_sym => value[k] }
      end

      def dump_data(value)
        return if value.nil?
        packed = MessagePack.pack(Type!(value, Hash, Array, Integer, String))
        ::Sequel.blob(packed)
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
        filters = filters.each.with_object({}) { |(k, v), hash| hash[k.to_s] = v }

        unknown = filters.keys - META_DATA.fetch(what)
        if what == :execution_plan
          unknown -= %w[uuid caller_execution_plan_id caller_action_id delayed]

          if filters.key?('caller_action_id') && !filters.key?('caller_execution_plan_id')
            raise ArgumentError, "caller_action_id given but caller_execution_plan_id missing"
          end

          if filters.key?('caller_execution_plan_id')
            data_set = data_set.join_table(:inner, TABLES[:action], :execution_plan_uuid => :uuid)
                               .select_all(TABLES[:execution_plan]).distinct
          end
          if filters.key?('delayed')
            filters.delete('delayed')
            data_set = data_set.join_table(:inner, TABLES[:delayed], :execution_plan_uuid => :uuid)
                               .select_all(TABLES[:execution_plan]).distinct
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
        rescue ::Sequel::DatabaseConnectionError, ::Sequel::DatabaseDisconnectError => e
          attempts += 1
          log(:error, e)
          if attempts > MAX_RETRIES
            log(:error, "The number of MAX_RETRIES exceeded")
            raise Errors::FatalPersistenceError.delegate(e)
          else
            log(:error, "Persistence retry no. #{attempts}")
            sleep RETRY_DELAY
            retry
          end
        rescue Exception => e
          raise Errors::PersistenceError.delegate(e)
        end
      end

      def execution_plan_column_map(plan)
        plan[:id] = plan[:uuid] unless plan[:uuid].nil?
        plan
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
