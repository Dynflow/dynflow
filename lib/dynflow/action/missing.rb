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
      raise StandardError,
            "The action class was not found and therefore plan phase failed, this can happen if the action was added/renamed but the executor was not restarted."
    end

    def run
      raise StandardError,
            "The action class was not found and therefore run phase failed, this can happen if the action was added/renamed but the executor was not restarted."
    end

    def finalize
      raise StandardError,
            "The action class was not found and therefore finalize phase failed, this can happen if the action was added/renamed but the executor was not restarted."
    end
  end
end
