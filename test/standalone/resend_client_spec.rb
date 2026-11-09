# frozen_string_literal: true
require_relative "spec_helper"

RSpec.describe SharedInbox::ResendClient do
  it "retrieves the complete received email from the fixed HTTPS API" do
    req = stub_request(:get, "https://api.resend.com/emails/receiving/email-1")
      .with(headers: { "Authorization" => "Bearer test-secret" }).to_return(body: mail.to_json)
    expect(described_class.new.receive("email-1")["text"]).to eq("Please help")
    expect(req).to have_been_requested.once
  end
  it "posts an idempotent email" do
    req = stub_request(:post, "https://api.resend.com/emails")
      .with(headers: { "Idempotency-Key" => "unique-key" }, body: { from: "support@example.com" }.to_json)
      .to_return(body: { id: "sent-id" }.to_json)
    expect(described_class.new.send_email({ from: "support@example.com" }, key: "unique-key")).to eq("id" => "sent-id")
    expect(req).to have_been_requested.once
  end
  it "does not allow webhook IDs to change the API path" do
    expect { described_class.new.receive("../../other") }.to raise_error(described_class::Error, "invalid_email_id")
  end
  it "keeps provider response bodies out of exceptions" do
    stub_request(:get, "https://api.resend.com/emails/receiving/email-1").to_return(status: 403, body: "private data")
    expect { described_class.new.receive("email-1") }.to raise_error(described_class::Error, "resend_http_403")
  end
  it "handles timeouts and invalid JSON" do
    stub_request(:get, "https://api.resend.com/emails/receiving/email-1").to_timeout
    expect { described_class.new.receive("email-1") }.to raise_error(described_class::Error, "resend_network_error")
    stub_request(:get, "https://api.resend.com/emails/receiving/email-1").to_return(body: "not JSON")
    expect { described_class.new.receive("email-1") }.to raise_error(described_class::Error, "resend_invalid_json")
  end
end
