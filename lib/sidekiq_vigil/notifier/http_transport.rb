# frozen_string_literal: true

require "net/http"
require "uri"

module SidekiqVigil
  module Notifier
    class HttpTransport
      Response = Data.define(:code, :body) do
        def success?
          code.to_i.between?(200, 299)
        end
      end

      def post(url, body, headers: {})
        uri = URI.parse(url)
        raise Error, "notification URL must use HTTP or HTTPS" unless %w[http https].include?(uri.scheme)

        request = Net::HTTP::Post.new(uri.request_uri, { "Content-Type" => "application/json" }.merge(headers))
        request.body = body
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.open_timeout = 5
          http.read_timeout = 10
          http.request(request)
        end
        Response.new(code: response.code, body: response.body)
      rescue URI::InvalidURIError, SocketError, SystemCallError, Timeout::Error => e
        raise Error, "notification request failed (#{e.class})"
      end
    end
  end
end
