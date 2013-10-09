module Dynflow
  # for cases the serialized action was renamed and it's not available
  # in the code base anymore.
  class Action::Missing < Dynflow::Action

    def self.generate(action_name)
      Class.new(self).tap do |klass|
        klass.singleton_class.send(:define_method, :name) do
          action_name
        end
      end
    end

    def plan(*args)
      raise StandardError, "This action is not meant to be planned"
    end

    def run
      raise StandardError, "This action is not meant to be run"
    end

    def finalize
      raise StandardError, "This action is not meant to be finalized"
    end
  end
end
