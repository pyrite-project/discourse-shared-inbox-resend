# frozen_string_literal: true

require "openssl"
require "base64"

module SharedInbox
  class Signature
    class Invalid < StandardError; end

    def self.verify!(body:, id:, timestamp:, signatures:, secret:, now: Time.now.to_i)
      raise Invalid if id.to_s.empty? || !timestamp.to_s.match?(/\A\d{1,12}\z/)
      raise Invalid if (now - timestamp.to_i).abs > 300
      raise Invalid unless secret.to_s.start_with?("whsec_")
      key = Base64.strict_decode64(secret.delete_prefix("whsec_"))
      raise Invalid if key.empty?
      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, "#{id}.#{timestamp}.#{body}"))
      matched = signatures.to_s.split.any? do |signature|
        version, actual = signature.split(",", 2)
        version == "v1" && actual && actual.bytesize == expected.bytesize &&
          OpenSSL.fixed_length_secure_compare(actual, expected)
      end
      raise Invalid unless matched
      true
    rescue ArgumentError
      raise Invalid
    end
  end
end
