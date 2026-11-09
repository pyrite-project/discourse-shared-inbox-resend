# frozen_string_literal: true
require_relative "spec_helper"

RSpec.describe SharedInbox::Signature do
  let(:body) { '{"type":"email.received"}' }
  let(:secret) { "whsec_#{Base64.strict_encode64('signing-key')}" }
  let(:now) { 1_800_000_000 }
  def verify(body: self.body, timestamp: now.to_s, id: "msg_123", signature: nil, secret: self.secret)
    signed = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "signing-key", "msg_123.#{now}.#{self.body}"))
    described_class.verify!(body: body, id: id, timestamp: timestamp, signatures: signature || "v1,#{signed}", secret: secret, now: now)
  end
  it("accepts the exact raw signed body") { expect(verify).to eq(true) }
  it("rejects tampering") { expect { verify(body: body + " ") }.to raise_error(described_class::Invalid) }
  it("rejects a stale timestamp") { expect { verify(timestamp: (now - 301).to_s) }.to raise_error(described_class::Invalid) }
  it("rejects a future timestamp") { expect { verify(timestamp: (now + 301).to_s) }.to raise_error(described_class::Invalid) }
  it("rejects invalid secrets") { expect { verify(secret: "whsec_!") }.to raise_error(described_class::Invalid) }
  it("rejects missing id") { expect { verify(id: "") }.to raise_error(described_class::Invalid) }
  it("rejects wrong versions") { expect { verify(signature: "v2,abc") }.to raise_error(described_class::Invalid) }
  it("rejects invalid timestamps") { expect { verify(timestamp: "123x") }.to raise_error(described_class::Invalid) }
  it "accepts rotated signatures with one valid v1 signature" do
    signed = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "signing-key", "msg_123.#{now}.#{body}"))
    expect(verify(signature: "v1,old v1,#{signed}")).to eq(true)
  end
end
