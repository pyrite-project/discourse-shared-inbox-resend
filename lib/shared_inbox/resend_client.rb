# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module SharedInbox
  class ResendClient
    class Error < StandardError
      attr_reader :code
      def initialize(code)
        @code = code
        super(code)
      end
    end

    def receive(id)
      request(:get, "/emails/receiving/#{safe_id(id)}")
    end

    def send_email(payload, key:)
      request(:post, "/emails", payload: payload, key: key)
    end

    private

    def safe_id(id)
      raise Error, "invalid_email_id" unless id.to_s.match?(/\A[a-zA-Z0-9_-]{1,100}\z/)
      id
    end

    def request(method, path, payload: nil, key: nil)
      uri = URI("https://api.resend.com#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30
      http.write_timeout = 30
      req = (method == :get ? Net::HTTP::Get : Net::HTTP::Post).new(uri)
      req["Authorization"] = "Bearer #{SiteSetting.shared_inbox_resend_api_key}"
      req["Content-Type"] = "application/json"
      req["Idempotency-Key"] = key if key
      req.body = JSON.generate(payload) if payload
      result = http.request(req)
      # Do not log response bodies, which can contain addresses or provider data.
      raise Error, "resend_http_#{result.code}" unless result.is_a?(Net::HTTPSuccess)
      JSON.parse(result.body)
    rescue JSON::ParserError
      raise Error, "resend_invalid_json"
    rescue Timeout::Error, IOError, SystemCallError, OpenSSL::SSL::SSLError
      raise Error, "resend_network_error"
    end
  end
end
