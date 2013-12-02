module Dynflow
  module Executors
    class Parallel < Abstract
      class WorkQueue

        def initialize
          @stash = Hash.new { |hash, key| hash[key] = [] }
        end

        def push(key, work)
          @stash[key].push work
        end

        def shift(key)
          @stash[key].shift.tap { |work| @stash.delete(key) if @stash[key].empty? }
        end

        def present?(key)
          @stash.key?(key)
        end

        def empty?(key)
          !present?(key)
        end

        def size(key)
          return 0 if empty?(key)
          @stash[key].size
        end

        def first(key)
          return nil if empty?(key)
          @stash[key].first
        end
      end
    end
  end
end
