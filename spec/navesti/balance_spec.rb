# frozen_string_literal: true

RSpec.describe Navesti::Balance do
  def money(minor, cur = "EUR")
    Navesti::Money.new(amount_minor: minor, currency: cur)
  end

  it "exposes flat minor-unit accessors matching the port contract" do
    balance = described_class.new(
      provider: "lhv", provider_account_id: "acc-1", currency: "EUR",
      available: money(12_350), booked: money(12_000)
    )
    expect(balance.available_amount_minor).to eq(12_350)
    expect(balance.booked_amount_minor).to eq(12_000)
    expect(balance.currency).to eq("EUR")
  end

  it "returns nil minor accessors when a balance type is absent" do
    balance = described_class.new(
      provider: "lhv", provider_account_id: "acc-1", currency: "EUR",
      available: money(75_00)
    )
    expect(balance.available_amount_minor).to eq(7_500)
    expect(balance.booked_amount_minor).to be_nil
  end

  it "requires a real ISO-4217 currency (never the 'XXX' container sentinel)" do
    expect do
      described_class.new(provider: "lhv", provider_account_id: "a", currency: "XXX", available: money(1, "EUR"))
    end.to raise_error(Navesti::ValidationError, /ISO-4217/)
  end

  it "requires at least one of available or booked" do
    expect do
      described_class.new(provider: "lhv", provider_account_id: "a", currency: "EUR")
    end.to raise_error(Navesti::ValidationError, /at least one/)
  end

  it "rejects a money currency that disagrees with the balance currency" do
    expect do
      described_class.new(provider: "lhv", provider_account_id: "a", currency: "EUR", available: money(1, "GBP"))
    end.to raise_error(Navesti::ValidationError, /does not match/)
  end
end
