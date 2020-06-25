# frozen_string_literal: true
require_relative 'test_helper'

module Dynflow
  module UtilsTest
    describe ::Dynflow::Utils::PriorityQueue do
      let(:queue) { Utils::PriorityQueue.new }

      it 'can insert elements' do
        queue.push 1
        _(queue.top).must_equal 1
        queue.push 2
        _(queue.top).must_equal 2
        queue.push 3
        _(queue.top).must_equal 3
        _(queue.to_a).must_equal [1, 2, 3]
      end

      it 'can override the comparator' do
        queue = Utils::PriorityQueue.new { |a, b| b <=> a }
        queue.push 1
        _(queue.top).must_equal 1
        queue.push 2
        _(queue.top).must_equal 1
        queue.push 3
        _(queue.top).must_equal 1
        _(queue.to_a).must_equal [3, 2, 1]
      end

      it 'can inspect top element without removing it' do
        assert_nil queue.top
        queue.push(1)
        _(queue.top).must_equal 1
        queue.push(3)
        _(queue.top).must_equal 3
        queue.push(2)
        _(queue.top).must_equal 3
      end

      it 'can report size' do
        count = 5
        count.times { queue.push 1 }
        _(queue.size).must_equal count
      end

      it 'pops elements in correct order' do
        queue.push 1
        queue.push 3
        queue.push 2
        _(queue.pop).must_equal 3
        _(queue.pop).must_equal 2
        _(queue.pop).must_equal 1
        assert_nil queue.pop
      end
    end

    # rubocop:disable Style/IndentArray
    describe ::Dynflow::Utils::DependencyGraph do
      let(:empty_graph) { Utils::DependencyGraph.new }
      let(:graph) do
        graph = empty_graph
        graph.add 1, []
        graph.add 2, 1
        graph.add 3, 2
        graph.add 4, 1
        graph.add 5, 1
        graph.add 7, [3, 4, 5]
        graph.add 8, 7
        graph
      end

      it "is empty by default" do
        assert empty_graph.empty?
        _(empty_graph.unblocked_nodes).must_be :empty?
        refute empty_graph.unresolved?
        _(empty_graph.levels.to_a).must_equal []
      end

      it "can block and unblock nodes" do
        _(graph.unblocked_nodes).must_equal [1]
        graph.block 1
        _(graph.unblocked_nodes).must_equal []
        graph.unblock 1
        _(graph.unblocked_nodes).must_equal [1]
      end

      it "can satisfy nodes" do
        _(graph.unblocked_nodes).must_equal [1]
        graph.satisfy 1
        _(graph.unblocked_nodes).must_equal [2, 4, 5]
      end

      it "returns nodes in levels correctly" do
        _(graph.levels.to_a).must_equal [[1],
                                         [2, 4, 5],
                                         [3],
                                         [7],
                                         [8]]
      end

      it "can convert single element graph to a flow" do
        # 1
        graph = Utils::DependencyGraph.new
        graph.add 1, []
        flow = graph.to_flow
        _(flow).must_equal Flows::Atom.new(1)
      end

      it "can convert sequence graph to a flow" do
        # 1 - 2
        graph = Utils::DependencyGraph.new
        graph.add 1, []
        graph.add 2, [1]
        flow = graph.to_flow
        _(flow).must_equal Flows::Sequence.new([
          Flows::Atom.new(1),
          Flows::Atom.new(2)
        ])
      end

      it "can convert a forest to a flow" do
        # 1
        # 2
        # 3
        graph = Utils::DependencyGraph.new
        graph.add 1, []
        graph.add 2, []
        graph.add 3, []
        flow = graph.to_flow
        _(flow).must_equal Flows::Concurrence.new([
          Flows::Atom.new(1),
          Flows::Atom.new(2),
          Flows::Atom.new(3)
        ])
      end

      it "can convert a combined graph to a flow" do
        #           4 --
        #          /     \
        # 1 - 2 - 3       7
        #          \     /
        #           5 - 6
        graph = Utils::DependencyGraph.new
        graph.add 1, []
        graph.add 2, [1]
        graph.add 3, [2]
        graph.add 4, [3]
        graph.add 5, [3]
        graph.add 6, [5]
        graph.add 7, [4, 6]
        flow = graph.to_flow

        _(flow).must_equal Flows::Sequence.new([
          Flows::Atom.new(1),
          Flows::Atom.new(2),
          Flows::Atom.new(3),
          Flows::Concurrence.new([
            Flows::Atom.new(4),
            Flows::Sequence.new([
              Flows::Atom.new(5),
              Flows::Atom.new(6)
            ])
          ]),
          Flows::Atom.new(7)
        ])
      end

      let(:complex_graph) do
        #         _9
        #        /  \
        #   3 - 7    13
        #  /     \  /  \
        # 1       10   16 ----- 17
        #  \          /  \     /
        #   4 --------    \   /
        #         11       \ /
        #        /  \       X
        #   5 - 8    14    / \
        #  /     \  /  \  /   \
        # 2       12    15 --- 18
        #  \           /
        #   6 ---------
        #
        graph = Utils::DependencyGraph.new
        graph.add 1, []
        graph.add 3, 1
        graph.add 7, 3
        graph.add 9, 7
        graph.add 10, 7
        graph.add 13, [9, 10]
        graph.add 4, 1
        graph.add 16, [4, 13]
        graph.add 2, []
        graph.add 5, 2
        graph.add 8, 5
        graph.add 11, 8
        graph.add 12, 8
        graph.add 14, [11, 12]
        graph.add 6, 2
        graph.add 15, [6, 14]
        graph.add 17, [15, 16]
        graph.add 18, [15, 16]
        graph
      end

      let(:complex_flow) do
        Flows::Sequence.new([
          Flows::Concurrence.new([
            Flows::Sequence.new([
              Flows::Atom.new(1),
              Flows::Concurrence.new([
                Flows::Sequence.new([
                  Flows::Atom.new(3),
                  Flows::Atom.new(7),
                  Flows::Concurrence.new([
                    Flows::Atom.new(9),
                    Flows::Atom.new(10)
                  ]),
                  Flows::Atom.new(13)
                ]),
                Flows::Atom.new(4)
              ]),
              Flows::Atom.new(16)
            ]),
            Flows::Sequence.new([
              Flows::Atom.new(2),
              Flows::Concurrence.new([
                Flows::Sequence.new([
                  Flows::Atom.new(5),
                  Flows::Atom.new(8),
                  Flows::Concurrence.new([
                    Flows::Atom.new(11),
                    Flows::Atom.new(12)
                  ]),
                  Flows::Atom.new(14)
                ]),
                Flows::Atom.new(6)
              ]),
              Flows::Atom.new(15)
            ])
          ]),
          Flows::Concurrence.new([
            Flows::Atom.new(17),
            Flows::Atom.new(18)
          ])
        ])
      end

      it "can convert a complex combined graph to a flow" do
        flow = complex_graph.to_flow
        _(flow).must_equal complex_flow
      end

      it "can convert a graph to flow and back" do
        loaded = Utils::DependencyGraph.new_from_flow(complex_graph.to_flow)
        _(loaded).must_equal complex_graph
      end

      it "can convert flow to a graph and back" do
        loaded = Utils::DependencyGraph.new_from_flow(complex_flow).to_flow
        _(loaded).must_equal complex_flow
      end
    end
  end
end
