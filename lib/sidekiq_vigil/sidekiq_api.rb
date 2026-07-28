# frozen_string_literal: true

module SidekiqVigil
  class SidekiqApi
    def queues(names = :all)
      return Sidekiq::Queue.all if names == :all

      Array(names).map { |name| Sidekiq::Queue.new(name.to_s) }
    end

    def retry_size
      Sidekiq::RetrySet.new.size
    end

    def dead_size
      Sidekiq::DeadSet.new.size
    end

    def processes
      Sidekiq::ProcessSet.new.to_a
    end

    def workers
      Sidekiq::Workers.new.map do |process_id, thread_id, work|
        {
          process_id:,
          thread_id:,
          work: {
            "run_at" => work.run_at.to_f,
            "payload" => work.payload
          }
        }
      end
    end

    def scheduled
      Sidekiq::ScheduledSet.new.to_a
    end
  end
end
