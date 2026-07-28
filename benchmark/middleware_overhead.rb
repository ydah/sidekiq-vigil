# frozen_string_literal: true

require "benchmark"
require "fileutils"
require "json"
require "sidekiq_vigil"

iterations = Integer(ENV.fetch("ITERATIONS", "100000"))
worker = Class.new
job = {}
queue = "benchmark"
middleware = SidekiqVigil::Middleware::Server.new
workload = lambda do
  value = 0
  20.times { |index| value += index }
  value
end

10_000.times { middleware.call(worker, job, queue, &workload) }
SidekiqVigil.collector.drain

without_middleware = Benchmark.realtime do
  iterations.times { workload.call }
end
with_middleware = Benchmark.realtime do
  iterations.times { middleware.call(worker, job, queue, &workload) }
end

overhead_seconds = with_middleware - without_middleware
overhead_per_job_us = overhead_seconds / iterations * 1_000_000
overhead_percent = without_middleware.positive? ? overhead_seconds / without_middleware * 100 : 0
result = {
  iterations:,
  without_middleware_seconds: without_middleware.round(6),
  with_middleware_seconds: with_middleware.round(6),
  overhead_per_job_microseconds: overhead_per_job_us.round(3),
  overhead_percent: overhead_percent.round(2)
}

FileUtils.mkdir_p("benchmark/results")
File.write("benchmark/results/middleware_overhead.json", JSON.pretty_generate(result))
puts JSON.pretty_generate(result)
warn("WARNING: middleware overhead exceeded 50µs/job") if overhead_per_job_us > 50
