# frozen_string_literal: true
require 'dynflow/serializable'
module Dynflow
  class Utils::DependencyGraph < Dynflow::Serializable
    attr_reader :graph

    def self.new_from_hash(hash, *args)
      self.new(Hash[hash.map { |k, v| [k.to_i, Set.new(v)] }])
    end

    def to_hash
      @graph.reduce({}) { |acc, (key, val)| acc.merge(key => val.to_a) }
    end

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

    def self.new_from_flow(flow)
      graph = self.new
      graph.load_flow flow
      graph
    end

    def load_flow(flow, parent_ids = [])
      case flow
      when Flows::Atom
        self.add(flow.step_id, parent_ids)
        [flow.step_id]
      when Flows::Sequence
        flow.flows.reduce(parent_ids) do |parent_ids, subflow|
          self.load_flow(subflow, parent_ids)
        end
      when Flows::Concurrence
        flow.flows.map do |subflow|
          self.load_flow(subflow, parent_ids)
        end
      end
    end

    def dup
      self.class.new(@graph.dup)
    end

    def to_flow
      self.dup.convert_to_flow
    end

    def convert_to_flow(discovered_nodes = [])
      available = self.unblocked_nodes
      return if available.count.zero?
      # Inspect all possible currently available branches
      subflows = available.map do |node|
        # Converting to flow consumes the graph, we need to work on a copy
        copy = self.dup
        # To invesetigate a single branch, we have to block all other branches
        (available - [node]).each { |n| copy.block n }
        # Unblock the current branch
        copy.satisfy node
        atom = Flows::Atom.new(node)
        # Recursively follow the branch
        subflow = copy.convert_to_flow
        case subflow
        when nil
          # If the branch ends with the current node, return an atom
          atom
        when Flows::Atom, Flows::Concurrence
          # If the next node in the branch would be a concurrent flow
          # or an atom Just create a sequence where the next node
          # follows the current one
          Flows::Sequence.new([atom, subflow])
        when Flows::Sequence
          # If a sequence is returned, prepend the current node to it,
          # consolidating it into one larger sequence
          flow = Flows::Sequence.new([atom])
          subflow.flows.each { |subflow| flow << subflow }
          flow
        end
      end

      # If there was only one branch, we can return its flow now
      return subflows.first if subflows.length == 1

      # All possible branches were explored, unlock all the nodes
      # we've met along the way
      subflows.map(&:all_step_ids).flatten.each { |n| satisfy n }

      # New branches could have been opened, follow down recursively
      following = self.convert_to_flow

      # At this point, we know there were more than 1 branches, join
      # them all into one concurrent flow
      aggregated_subflows = subflows.reduce(Flows::Concurrence.new([])) do |flow, subflow|
        flow << subflow
      end

      if following.nil?
        # If there was nothing to do after exploring the separate
        # branches, just return their aggregation
        aggregated_subflows
      else
        # New branch was followed, join it into sequence with aggregation of previous branches
        Flows::Sequence.new([aggregated_subflows, following])
      end
    end

    def ==(other)
      @graph == other.graph
    end
  end
end
