# frozen_string_literal: true

require "date"

module SidekiqVigil
  module Timezone
    MUTEX = Mutex.new

    module_function

    def local_time(time, zone)
      return time.getutc if zone == "UTC"
      return time.getlocal(zone) if zone.match?(/\A[+-]\d{2}:\d{2}\z/)

      MUTEX.synchronize do
        previous = ENV.fetch("TZ", nil)
        ENV["TZ"] = zone
        Time.at(time.to_f).localtime
      ensure
        ENV["TZ"] = previous
      end
    end

    def same_local_days_ago(time, days, zone)
      local = local_time(time, zone)
      date = local.to_date - days
      return Time.utc(date.year, date.month, date.day, local.hour, local.min, local.sec) if zone == "UTC"
      return Time.new(date.year, date.month, date.day, local.hour, local.min, local.sec, zone) if zone.match?(/\A[+-]\d{2}:\d{2}\z/)

      MUTEX.synchronize do
        previous = ENV.fetch("TZ", nil)
        ENV["TZ"] = zone
        Time.local(date.year, date.month, date.day, local.hour, local.min, local.sec)
      ensure
        ENV["TZ"] = previous
      end
    end
  end
end
