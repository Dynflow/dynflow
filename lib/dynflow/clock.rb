# frozen_string_literal: true

module Dynflow
  class Clock < Actor

    include Algebrick::Types

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

      def eql?(other)
        object_id == other.object_id
      end

      def hash
        object_id
      end

      def apply
        if Algebrick::Some[Object] === what
          who.send where, what.value
        else
          who.send where
        end
      end
    end

    def initialize(logger = nil)
      @logger = logger
      @timers = Utils::PriorityQueue.new { |a, b| b <=> a }
    end

    def default_reference_class
      ClockReference
    end

    def on_event(event)
      wakeup if event == :terminated
    end

    def tick
      run_ready_timers
      sleep_to first_timer
    end

    def add_timer(timer)
      @timers.push timer
      if @timers.size == 1
        sleep_to timer
      else
        wakeup if timer == first_timer
      end
    end

    private

    def run_ready_timers
      while first_timer && first_timer.when <= Time.now
        begin
          first_timer.apply
        rescue => e
          @logger && @logger.error("Failed to apply clock event #{first_timer}, exception: #{e}")
        end
        @timers.pop
      end
    end

    def first_timer
      @timers.top
    end

    def wakeup
      if @timer
        @timer.cancel
        tick unless terminating?
      end
    end

    def sleep_to(timer)
      return unless timer
      schedule(timer.when - Time.now) { reference.tell(:tick) unless terminating? }
      nil
    end

    def schedule(delay, &block)
      @timer = if delay.positive?
                 Concurrent::ScheduledTask.execute(delay, &block)
               else
                 yield
                 nil
               end
    end
  end

  class ClockReference < Concurrent::Actor::Reference
    include Algebrick::Types

    def current_time
      Time.now
    end

    def ping(who, time, with_what = nil, where = :<<, optional: false)
      Type! time, Time, Numeric
      time  = current_time + time if time.is_a? Numeric
      if who.is_a?(Action::Suspended)
        who.plan_event(with_what, time, optional: optional)
      else
        timer = Clock::Timer[who, time, with_what.nil? ? Algebrick::Types::None : Some[Object][with_what], where]
        self.tell([:add_timer, timer])
      end
    end
  end

end
