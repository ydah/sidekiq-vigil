# frozen_string_literal: true

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
  end
end
