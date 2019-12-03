# frozen_string_literal: true

module Dynflow
  class Utils::DependencyGraph

    def initialize(graph = nil)
      @graph = graph || Hash.new { |h, k| h[k] = Set.new }
    end

    def node_requirements(node)
      @graph[node]
    end

    def unresolved?
      @graph.any? { |step_id, requirements| requirements.any? }
    end

    def unblocked_nodes
      @graph.select { |k, v| v.empty? }.keys
    end

    def blocked_nodes
      @graph.select { |k, v| Set.new([k]) == v }.keys
    end

    def empty?
      @graph.empty?
    end

    def mark_satisfied(step_id, required_step_id)
      @graph[step_id].delete(required_step_id)
    end

    def satisfy(to_satisfy = unblocked_nodes)
      to_satisfy = [to_satisfy] unless to_satisfy.kind_of? Array
      to_satisfy &= unblocked_nodes | blocked_nodes
      return [] if to_satisfy.empty?
      @graph.each { |k, v| @graph[k] = v - to_satisfy }
      to_satisfy.each { |leaf| @graph.delete leaf }
      to_satisfy
    end

    def levels
      Enumerator.new do |y|
        until empty?
          nodes = unblocked_nodes
          y << nodes
          satisfy nodes
        end
      end
    end

    def add(node, requirements)
      requirements = [requirements] unless requirements.kind_of? Array
      @graph[node] = @graph[node] | requirements.flatten
    end

    def block(item)
      add item, item
    end

    def unblock(item)
      @graph[item] = @graph[item] - [item]
    end
  end
end
