require 'multi_json'
require 'active_support/hash_with_indifferent_access'


module Dynflow
  module PersistenceAdapters
    class SimpleFileStorage < Abstract
      include Algebrick::TypeCheck

      attr_reader :storage_dir

      def initialize(storage_dir)
        raise ArgumentError unless File.exist?(storage_dir) && File.directory?(storage_dir)
        @storage_dir = storage_dir
        Dir.mkdir(plans_dir) unless File.exist?(plans_dir)
        Dir.mkdir(actions_dir) unless File.exist?(actions_dir)
      end

      def load_execution_plan(execution_plan_id)
        load(plans_dir, execution_plan_id.to_s)
      end

      def save_execution_plan(execution_plan_id, value)
        save(plans_dir, execution_plan_id.to_s, value)
      end

      def load_action(execution_plan_id, action_id)
        load(actions_dir, execution_plan_id.to_s + action_id.to_s)
      end

      def save_action(execution_plan_id, action_id, value)
        save(actions_dir, execution_plan_id.to_s + action_id.to_s, value)
      end

      private

      def plans_dir
        "#{storage_dir}/plans"
      end

      def actions_dir
        "#{storage_dir}/actions"
      end

      def load(dir, file_name)
        if File.exist? "#{dir}/#{file_name}"
          File.open("#{dir}/#{file_name}", 'r') do |f|
            HashWithIndifferentAccess.new MultiJson.load(f.read)
          end
        else
          raise KeyError
        end
      end

      def save(dir, file_name, value)
        path = "#{dir}/#{file_name}"
        if value
          is_kind_of! value, Hash
          File.open(path, 'w') { |f| f.write MultiJson.dump(value) }
        else
          File.delete(path)
        end
        return value
      end
    end
  end
end
