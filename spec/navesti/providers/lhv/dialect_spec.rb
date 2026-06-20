# frozen_string_literal: true

RSpec.describe Navesti::Providers::LHV::Dialect do
  describe ".payment_status" do
    # raw => [status, safety_status, side_effect_possible] — the table in
    # docs/08-status-normalization.md. This is the safety contract; pin it.
    {
      "RCVD" => [:requires_authorization,         :pending,   false],
      "RVCD" => [:requires_authorization,         :pending,   false],
      "PATC" => [:partially_authorized,           :pending,   false],
      "ACSP" => [:pending_execution,              :pending,   true],
      "ACWC" => [:pending_execution_with_warning, :pending,   true],
      "ACSC" => [:confirmed,                      :confirmed, true],
      "RJCT" => [:rejected,                       :rejected,  false],
      "CANC" => [:cancelled,                      :rejected,  false],
      "PDNG" => [:pending_xml_signature,          :pending,   :unknown]
    }.each do |raw, (status, safety, side_effect)|
      it "maps #{raw} -> #{status} / #{safety} / side_effect=#{side_effect}" do
        result = described_class.payment_status(raw)
        expect(result.status).to eq(status)
        expect(result.safety_status).to eq(safety)
        expect(result.side_effect_possible).to eq(side_effect)
        expect(result.raw_status).to eq(raw)
      end
    end

    it "preserves the raw value even for unmapped codes" do
      result = described_class.payment_status("WAT")
      expect(result.raw_status).to eq("WAT")
    end

    it "never maps an unknown code to rejected, and keeps it unsafe" do
      result = described_class.payment_status("SOMETHING_NEW")
      expect(result.status).to eq(:unknown)
      expect(result.safety_status).to eq(:unknown)
      expect(result.safety_status).not_to eq(:rejected)
      expect(result.side_effect_possible).to eq(true)
    end

    it "RCVD and ACSP straddle the double-spend boundary" do
      expect(described_class.payment_status("RCVD").side_effect_possible).to eq(false)
      expect(described_class.payment_status("ACSP").side_effect_possible).to eq(true)
    end

    it "attaches the provider reference and raw evidence when given" do
      ref = Navesti::ProviderReference.new(value: "p-1", kind: :payment, connector: "lhv")
      result = described_class.payment_status("ACSC", provider_reference: ref, raw: { body: "{}" })
      expect(result.provider_reference).to eq(ref)
      expect(result.raw).to eq(body: "{}")
    end
  end

  describe ".access" do
    it "maps ENABLED and BLOCKED" do
      expect(described_class.access("ENABLED")).to eq(:enabled)
      expect(described_class.access("BLOCKED")).to eq(:blocked)
    end

    it "maps anything else to unknown" do
      expect(described_class.access("WHATEVER")).to eq(:unknown)
    end
  end

  describe ".consent_status" do
    {
      "received"       => :received,
      "valid"          => :valid,
      "rejected"       => :rejected,
      "expired"        => :expired,
      "revokedByPsu"   => :revoked_by_psu,
      "terminatedByTpp" => :terminated_by_tpp
    }.each do |raw, symbol|
      it "maps #{raw} -> #{symbol}" do
        expect(described_class.consent_status(raw)).to eq(symbol)
      end
    end

    it "maps an unknown consentStatus to :unknown (never :valid)" do
      expect(described_class.consent_status("WHATEVER")).to eq(:unknown)
      expect(described_class.consent_status("WHATEVER")).not_to eq(:valid)
    end
  end
end
