# frozen_string_literal: true

require "securerandom"

module SidekiqVigil
  class LeaderElection
    EXTEND_SCRIPT = <<~LUA
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("pexpire", KEYS[1], ARGV[2])
      end
      return 0
    LUA
    RELEASE_SCRIPT = <<~LUA
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
      end
      return 0
    LUA

    attr_reader :token

    def initialize(storage:, ttl:, token: SecureRandom.uuid)
      @storage = storage
      @ttl_ms = (ttl * 1000).to_i
      @token = token
      @leader = false
    end

    def acquire
      @leader = storage.acquire_lock("leader", token, ttl_ms: ttl_ms)
    end

    def extend
      @leader = storage.eval(EXTEND_SCRIPT, keys: ["leader"], argv: [token, ttl_ms]).to_i == 1
    end

    def leader?
      @leader
    end

    def release
      released = storage.eval(RELEASE_SCRIPT, keys: ["leader"], argv: [token]).to_i == 1
      @leader = false
      released
    rescue StandardError
      @leader = false
      false
    end

    private

    attr_reader :storage, :ttl_ms
  end
end
