# frozen_string_literal: true

RSpec.describe Navesti::Token do
  subject(:token) do
    described_class.new(
      access_token: "real-access-token", refresh_token: "real-refresh-token",
      token_type: "bearer", expires_in: 3599, scope: "psd2"
    )
  end

  it "exposes the real values via typed readers (the host needs them)" do
    expect(token.access_token).to eq("real-access-token")
    expect(token.refresh_token).to eq("real-refresh-token")
  end

  it "redacts token material from #to_h (the log/serialize/persist surface)" do
    h = token.to_h
    expect(h[:access_token]).to eq("[REDACTED]")
    expect(h[:refresh_token]).to eq("[REDACTED]")
    expect(h[:scope]).to eq("psd2")
    serialized = JSON.generate(h)
    expect(serialized).not_to include("real-access-token")
    expect(serialized).not_to include("real-refresh-token")
  end

  it "leaves refresh_token nil (not masked) when absent" do
    t = described_class.new(access_token: "a")
    expect(t.to_h[:refresh_token]).to be_nil
  end

  it "exposes real values only via the deliberately-named #to_secret_h" do
    s = token.to_secret_h
    expect(s[:access_token]).to eq("real-access-token")
    expect(s[:refresh_token]).to eq("real-refresh-token")
  end

  it "redacts #inspect" do
    expect(token.inspect).not_to include("real-access-token")
    expect(token.inspect).to include("[REDACTED]")
  end
end
