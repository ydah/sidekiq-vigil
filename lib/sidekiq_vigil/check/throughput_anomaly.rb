# frozen_string_literal: true

module SidekiqVigil
  module Check
    class ThroughputAnomaly < Base
      WINDOW_MINUTES = 60

      def call
        baseline = baseline_samples
        return insufficient_result(baseline.length) if baseline.length < options.fetch(:min_samples, 3)

        expected = median(baseline)
        current = window_total(clock.call)
        drop = expected.positive? ? 1 - current.fdiv(expected) : 0.0
        severity = drop >= options.fetch(:drop_pct, 0.5) ? :warn : :ok
        Result.new(
          check_name:,
          severity:,
          value: current,
          threshold: expected * (1 - options.fetch(:drop_pct, 0.5)),
          message: format(
            "%<current>d jobs vs %<expected>.1f baseline (%<drop>.1f%% drop)",
            current:,
            expected:,
            drop: drop * 100
          ),
          metadata: { baseline: expected, samples: baseline.length, drop_pct: drop }
        )
      end

      private

      def baseline_samples
        days = options.fetch(:baseline_days, 7)
        (1..days).filter_map do |days_ago|
          sample_time = Timezone.same_local_days_ago(clock.call, days_ago, options.fetch(:timezone, "UTC"))
          sample = window_total(sample_time)
          sample if sample.positive?
        end
      end

      def window_total(time)
        local = Timezone.local_time(time, options.fetch(:timezone, "UTC"))
        WINDOW_MINUTES.times.sum do |offset|
          minute = local - (offset * 60)
          storage.hash_get_all("stats:#{minute.getutc.strftime('%Y%m%d%H%M')}").fetch("processed", 0).to_i
        end
      end

      def median(values)
        sorted = values.sort
        middle = sorted.length / 2
        return sorted[middle].to_f if sorted.length.odd?

        (sorted[middle - 1] + sorted[middle]).fdiv(2)
      end

      def insufficient_result(samples)
        Result.new(
          check_name:,
          severity: :ok,
          value: nil,
          message: "insufficient baseline samples (#{samples}/#{options.fetch(:min_samples, 3)})",
          metadata: { insufficient_samples: true, samples: }
        )
      end
    end
  end
end
