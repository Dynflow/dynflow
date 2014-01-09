module Dynflow
  require 'set'

  class Clock < MicroActor

    include Algebrick::Types

    Tick  = Algebrick.atom
    Timer = Algebrick.type do
      fields! who:   Object, # to ping back
              when:  Time, # to deliver
              what:  Maybe[Object], # to send
              where: Symbol # it should be delivered, which method
    end

    module Timer
      def self.[](*fields)
        super(*fields).tap { |v| Match! v.who, -> who { who.respond_to? v.where } }
      end

      include Comparable

      def <=>(other)
        Type! other, self.class
        self.when <=> other.when
      end
    end

    Pills = Algebrick.type do
      variants None = atom,
               Took = atom,
               Pill = type { fields Float }
    end

    def ping(who, time, with_what = nil, where = :<<)
      Type! time, Time, Numeric
      time = Time.now + time if time.is_a? Numeric
      self << Timer[who, time, with_what.nil? ? None : Some[Object][with_what], where]
    end

    private

    def delayed_initialize
      @timers        = SortedSet.new
      @sleeping_pill = None
      @sleep_barrier = Mutex.new
      @sleeper       = Thread.new { sleeping }
      Thread.pass until @sleep_barrier.locked? || @sleeper.status == 'sleep'
    end

    def termination
      @sleeper.kill
      super
    end

    def on_message(message)
      match message,
            Tick >-> do
              run_ready_timers
              sleep_to first_timer
            end,
            ~Timer >-> timer do
              @timers.add timer
              if @timers.size == 1
                sleep_to timer
              else
                wakeup if timer == first_timer
              end
            end
    end

    def run_ready_timers
      while first_timer && first_timer.when <= Time.now
        if Some === first_timer.what
          first_timer.who.send first_timer.where, first_timer.what.value
        else
          first_timer.who.send first_timer.where
        end
        @timers.delete(first_timer)
      end
    end

    def first_timer
      @timers.first
    end

    def wakeup
      while @sleep_barrier.synchronize { Pill === @sleeping_pill }
        Thread.pass
      end
      @sleep_barrier.synchronize do
        @sleeper.wakeup if Took === @sleeping_pill
      end
    end

    def sleep_to(timer)
      return unless timer
      sec = [timer.when - Time.now, 0.0].max
      @sleep_barrier.synchronize do
        @sleeping_pill = Pill[sec]
        @sleeper.wakeup
      end
    end

    def sleeping
      @sleep_barrier.synchronize do
        loop do
          @sleeping_pill = None
          @sleep_barrier.sleep
          pill           = @sleeping_pill
          @sleeping_pill = Took
          @sleep_barrier.sleep pill.value
          self << Tick
        end
      end
    end

  end
end


