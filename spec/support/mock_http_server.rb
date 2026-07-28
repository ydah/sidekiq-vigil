# frozen_string_literal: true

require "json"
require "socket"

class MockHttpServer
  attr_reader :messages, :port

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.local_address.ip_port
    @messages = Queue.new
    @thread = Thread.new { serve }
  end

  def url
    "http://127.0.0.1:#{port}/events"
  end

  def stop
    @server.close
    @thread.join(1)
  rescue IOError
    nil
  end

  private

  def serve
    loop do
      client = @server.accept
      handle(client)
    end
  rescue IOError, Errno::EBADF
    nil
  end

  def handle(client)
    client.gets
    headers = read_headers(client)
    body = client.read(headers.fetch("content-length", "0").to_i)
    messages << JSON.parse(body)
    client.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK")
  ensure
    client.close
  end

  def read_headers(client)
    {}.tap do |headers|
      while (line = client.gets)
        break if line == "\r\n"

        name, value = line.split(":", 2)
        headers[name.downcase] = value.strip
      end
    end
  end
end
