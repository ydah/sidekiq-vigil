# frozen_string_literal: true

require "json"

module SidekiqVigil
  class Storage
    class MissingTTL < ArgumentError; end

    attr_reader :prefix

    def initialize(redis: nil, key_prefix: "default")
      @redis = redis
      @prefix = "vigil:#{key_prefix}:"
    end

    def key(suffix)
      "#{prefix}#{suffix}"
    end

    def set(suffix, value, ttl:)
      require_ttl!(ttl)
      with_redis { |redis| redis.call("SET", key(suffix), value, "EX", ttl) }
    end

    def get(suffix)
      with_redis { |redis| redis.call("GET", key(suffix)) }
    end

    def hash_write(suffix, values, ttl:)
      require_ttl!(ttl)
      return if values.empty?

      with_redis do |redis|
        redis.pipelined do |pipeline|
          pipeline.call("HSET", key(suffix), *values.flatten)
          pipeline.call("EXPIRE", key(suffix), ttl)
        end
      end
    end

    def hash_increment(suffix, values, ttl:)
      require_ttl!(ttl)
      return if values.empty?

      with_redis do |redis|
        redis.pipelined do |pipeline|
          values.each do |field, amount|
            command = amount.is_a?(Integer) ? "HINCRBY" : "HINCRBYFLOAT"
            pipeline.call(command, key(suffix), field, amount)
          end
          pipeline.call("EXPIRE", key(suffix), ttl)
        end
      end
    end

    def managed_hash_write(suffix, field, value)
      with_redis { |redis| redis.call("HSET", key(suffix), field, value) }
    end

    def hash_get_all(suffix)
      with_redis { |redis| redis.call("HGETALL", key(suffix)) }
    end

    def hash_delete(suffix, *fields)
      return if fields.empty?

      with_redis { |redis| redis.call("HDEL", key(suffix), *fields) }
    end

    def list_push(suffix, value, ttl:, limit: 30)
      require_ttl!(ttl)
      with_redis do |redis|
        redis.pipelined do |pipeline|
          pipeline.call("RPUSH", key(suffix), value)
          pipeline.call("LTRIM", key(suffix), -limit, -1)
          pipeline.call("EXPIRE", key(suffix), ttl)
        end
      end
    end

    def list_range(suffix)
      with_redis { |redis| redis.call("LRANGE", key(suffix), 0, -1) }
    end

    def delete(suffix)
      with_redis { |redis| redis.call("DEL", key(suffix)) }
    end

    def scan(pattern = "*")
      with_redis do |redis|
        cursor = "0"
        keys = []
        loop do
          cursor, batch = redis.call("SCAN", cursor, "MATCH", key(pattern), "COUNT", 100)
          keys.concat(batch)
          break if cursor == "0"
        end
        keys
      end
    end

    def acquire_lock(suffix, token, ttl_ms:)
      with_redis { |redis| redis.call("SET", key(suffix), token, "NX", "PX", ttl_ms) == "OK" }
    end

    def eval(script, keys:, argv:)
      namespaced_keys = keys.map { |item| key(item) }
      with_redis { |redis| redis.call("EVAL", script, namespaced_keys.length, *namespaced_keys, *argv) }
    end

    def ping
      with_redis { |redis| redis.call("PING") }
    end

    def info(section = nil)
      with_redis { |redis| parse_info(redis.call("INFO", *Array(section))) }
    end

    private

    def require_ttl!(ttl)
      raise MissingTTL, "a positive ttl is required" unless ttl.is_a?(Numeric) && ttl.positive?
    end

    def with_redis(&)
      return yield @redis if @redis

      Sidekiq.redis(&)
    end

    def parse_info(raw)
      raw.each_line.filter_map do |line|
        next if line.start_with?("#") || !line.include?(":")

        line.strip.split(":", 2)
      end.to_h
    end
  end
end
