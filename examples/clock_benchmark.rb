require 'dynflow'
require 'benchmark'

class Receiver
  def initialize(limit, future)
    @limit = limit
    @future = future
    @counter = 0
  end

  def null
    @counter += 1
    @future.success(true) if @counter >= @limit
  end
end


def test_case(count)
  future   = Concurrent.future
  clock    = Dynflow::Clock.spawn(:name => 'clock')
  receiver = Receiver.new(count, future)

  count.times do
    clock.ping(receiver, 0, nil, :null)
  end
  future.wait
end

Benchmark.bm do |bm|
  bm.report('   100') { test_case 100 }
  bm.report('  1000') { test_case 1_000 }
  bm.report('  5000') { test_case 5_000 }
  bm.report(' 10000') { test_case 10_000 }
  bm.report(' 50000') { test_case 50_000 }
  bm.report('100000') { test_case 100_000 }
end
