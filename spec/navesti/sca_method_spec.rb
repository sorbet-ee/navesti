# frozen_string_literal: true

RSpec.describe Navesti::ScaMethod do
  it "carries the method id, type, and name" do
    m = described_class.new(method_id: "SID", authentication_type: "PUSH_OTP", name: "Smart-ID")
    expect(m.method_id).to eq("SID")
    expect(m.authentication_type).to eq("PUSH_OTP")
    expect(m.name).to eq("Smart-ID")
    expect(m).to be_frozen
  end

  it "requires a method_id" do
    expect { described_class.new(method_id: "") }
      .to raise_error(Navesti::ValidationError, /method_id/)
  end
end
