# frozen_string_literal: true

module RedisHelpers
  def redis
    @redis ||= RedisClient.config(url: ENV.fetch("VIGIL_REDIS_URL", "redis://127.0.0.1:16379/15")).new_client
  end

  def storage(prefix: "spec")
    SidekiqVigil::Storage.new(redis:, key_prefix: prefix)
  end
end

RSpec.configure do |config|
  config.include RedisHelpers, :redis

  config.before(:each, :redis) do
    redis.call("FLUSHDB")
  rescue RedisClient::CannotConnectError => e
    skip("Redis integration server is unavailable: #{e.message}")
  end
end
