# frozen_string_literal: true

require "json"
require "optparse"

module SidekiqVigil
  class CLI
    EXIT_OK = 0
    EXIT_ALERT = 2
    EXIT_UNAVAILABLE = 3

    def initialize(config: SidekiqVigil.config, storage: nil, out: $stdout, err: $stderr, checker_factory: nil)
      @config = config
      @resolved_storage = storage
      @out = out
      @err = err
      @checker_factory = checker_factory || -> { Checker.new(storage: resolved_storage, config:) }
    end

    def run(arguments)
      args = arguments.dup
      load_config(extract_config_path(args))
      configure_sidekiq_api
      command = args.shift || "run"
      handler = command_handlers(args)[command]
      return unknown_command(command) unless handler

      handler.call
    rescue OptionParser::ParseError, ConfigError, ArgumentError => e
      err.puts(e.message)
      EXIT_UNAVAILABLE
    end

    private

    attr_reader :config, :out, :err, :checker_factory

    def resolved_storage
      @resolved_storage ||= SidekiqVigil.build_storage(config)
    end

    def command_handlers(args)
      {
        "run" => -> { run_forever(args) },
        "check" => -> { run_check(args) },
        "status" => -> { print_status(args) },
        "test-notify" => -> { test_notify(args) },
        "mute" => -> { mute(args) },
        "unmute" => -> { unmute(args) }
      }
    end

    def extract_config_path(args)
      index = args.index("--config") || args.index("-c")
      return unless index

      option = args.delete_at(index)
      path = args.delete_at(index)
      raise OptionParser::MissingArgument, option unless path

      path
    end

    def load_config(path)
      return unless path
      raise ConfigError, "config file not found: #{path}" unless File.file?(path)

      Kernel.load(File.expand_path(path))
      config.validate!
    end

    def configure_sidekiq_api
      return unless config.redis

      Sidekiq.configure_client { |sidekiq| sidekiq.redis = config.redis.compact }
    end

    def run_forever(_args = [])
      checker = checker_factory.call
      reader, writer = IO.pipe
      previous = install_signal_handlers(writer)
      checker.start
      reader.read(1)
      checker.stop
      EXIT_OK
    ensure
      restore_signal_handlers(previous) if previous
      reader&.close
      writer&.close
    end

    def install_signal_handlers(writer)
      %w[INT TERM].to_h do |signal|
        previous = Signal.trap(signal) { writer.write_nonblock(signal, exception: false) }
        [signal, previous]
      end
    end

    def restore_signal_handlers(previous)
      previous.each { |signal, handler| Signal.trap(signal, handler) }
    end

    def run_check(args)
      parser = OptionParser.new
      once = false
      parser.on("--once") { once = true }
      parser.parse!(args)
      raise OptionParser::InvalidOption, "check requires --once" unless once

      results = checker_factory.call.run_once
      return EXIT_UNAVAILABLE if results == false

      print_results(results)
      results.all?(&:ok?) ? EXIT_OK : EXIT_ALERT
    end

    def print_results(results)
      results.each do |result|
        out.puts([result.severity.to_s.upcase, result.check_name, result.target, result.message].compact.join("\t"))
      end
    end

    def print_status(_args = [])
      raw = resolved_storage.get("snapshot")
      return unavailable("No snapshot available") unless raw

      snapshot = JSON.parse(raw)
      out.puts("Snapshot: #{snapshot.fetch('timestamp')}")
      snapshot.fetch("results").each do |result|
        out.puts([result.fetch("severity").upcase, result.fetch("check_name"), result.fetch("target")].join("\t"))
      end
      EXIT_OK
    end

    def test_notify(_args = [])
      result = Result.new(
        check_name: "test_notification",
        severity: :warn,
        message: "Sidekiq Vigil test notification"
      )
      state = Alert::State.new(status: "firing", severity: "warn")
      event = Alert::Event.new(result:, transition: :firing, state:, history: [], timestamp: Time.now)
      manager = Notifier::Manager.new(notifiers: Notifier::Factory.build(config))
      manager.notify([event])
      out.puts("Test notification sent to #{config.runnable_notifiers.length} notifier(s)")
      EXIT_OK
    end

    def mute(args)
      reason = nil
      parser = OptionParser.new
      parser.on("--reason REASON") { |value| reason = value }
      parser.parse!(args)
      duration = parse_duration(args.shift)
      raise OptionParser::InvalidArgument, "mute duration is required" unless duration

      alert_mute.mute(duration, reason:)
      out.puts("Muted for #{duration} seconds")
      EXIT_OK
    end

    def unmute(_args = [])
      alert_mute.unmute
      out.puts("Mute cleared")
      EXIT_OK
    end

    def alert_mute
      Alert::Mute.new(
        storage: resolved_storage,
        schedules: config.alerting.mutes,
        timezone: config.timezone
      )
    end

    def parse_duration(value)
      return unless value

      match = value.match(/\A(\d+)([smhd]?)\z/)
      raise OptionParser::InvalidArgument, "invalid duration: #{value}" unless match

      Integer(match[1]) * { "" => 1, "s" => 1, "m" => 60, "h" => 3_600, "d" => 86_400 }.fetch(match[2])
    end

    def unavailable(message)
      err.puts(message)
      EXIT_UNAVAILABLE
    end

    def unknown_command(command)
      err.puts("Unknown command: #{command}")
      err.puts(usage)
      EXIT_UNAVAILABLE
    end

    def usage
      "Usage: vigil [--config FILE] [run|check --once|status|test-notify|mute DURATION|unmute]"
    end
  end
end
