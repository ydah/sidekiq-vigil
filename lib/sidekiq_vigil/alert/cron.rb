# frozen_string_literal: true

module SidekiqVigil
  module Alert
    class Cron
      Field = Data.define(:values, :wildcard)

      FIELD_RANGES = [
        (0..59),
        (0..23),
        (1..31),
        (1..12),
        (0..7)
      ].freeze

      def initialize(expression)
        fields = expression.to_s.split
        raise ConfigError, "mute cron must contain five fields" unless fields.length == FIELD_RANGES.length

        @fields = fields.zip(FIELD_RANGES).map { |field, range| parse_field(field, range) }
      end

      def match?(time)
        minute, hour, day, month, weekday = fields
        fixed_fields = [[minute, time.min], [hour, time.hour], [month, time.month]]
        return false unless fixed_fields.all? { |field, value| field.values.include?(value) }

        day_matches = day.values.include?(time.day)
        weekday_matches = weekday.values.include?(time.wday)
        return day_matches || weekday_matches unless day.wildcard || weekday.wildcard

        day_matches && weekday_matches
      end

      private

      attr_reader :fields

      def parse_field(source, range)
        wildcard = source.start_with?("*")
        values = source.split(",").flat_map { |part| expand_part(part, range) }.map do |value|
          normalize_weekday(value, range)
        end
        raise ConfigError, "mute cron field #{source.inspect} selects no values" if values.empty?

        Field.new(values: values.uniq.freeze, wildcard:)
      rescue ArgumentError
        raise ConfigError, "invalid mute cron field #{source.inspect}"
      end

      def expand_part(part, range)
        base, raw_step = split_part(part)
        step = parse_step(raw_step)
        values = base_values(base, range, stepped: !raw_step.nil?)
        values.each_with_index.filter_map { |value, index| value if (index % step).zero? }
      end

      def split_part(part)
        base, raw_step, extra = part.split("/", 3)
        raise ArgumentError if base.nil? || base.empty? || extra

        [base, raw_step]
      end

      def parse_step(raw_step)
        return 1 unless raw_step

        step = Integer(raw_step, 10)
        raise ArgumentError unless step.positive?

        step
      end

      def base_values(base, range, stepped:)
        return range.to_a if base == "*"

        if base.include?("-")
          first, last, extra = base.split("-", 3)
          raise ArgumentError if extra

          first = bounded_integer(first, range)
          last = bounded_integer(last, range)
          raise ArgumentError if first > last

          return (first..last).to_a
        end

        first = bounded_integer(base, range)
        return (first..range.end).to_a if stepped

        [first]
      end

      def bounded_integer(value, range)
        integer = Integer(value, 10)
        raise ArgumentError unless range.cover?(integer)

        integer
      end

      def normalize_weekday(value, range)
        range.end == 7 && value == 7 ? 0 : value
      end
    end
  end
end
