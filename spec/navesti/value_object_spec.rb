# frozen_string_literal: true

RSpec.describe Navesti::ValueObject do
  it "freezes instances at construction" do
    money = Navesti::Money.new(amount_minor: 1, currency: "EUR")
    expect(money).to be_frozen
  end

  it "raises on a missing required attribute" do
    expect { Navesti::Money.new(currency: "EUR") }
      .to raise_error(Navesti::ValidationError, /missing required attribute :amount_minor/)
  end

  it "raises on an unknown attribute" do
    expect { Navesti::Money.new(amount_minor: 1, currency: "EUR", bogus: 1) }
      .to raise_error(Navesti::ValidationError, /unknown attribute/)
  end

  it "compares by value" do
    a = Navesti::Money.new(amount_minor: 1, currency: "EUR")
    b = Navesti::Money.new(amount_minor: 1, currency: "EUR")
    expect(a).to eq(b)
    expect(a.hash).to eq(b.hash)
  end

  it "returns a new frozen instance from #with" do
    a = Navesti::Money.new(amount_minor: 1, currency: "EUR")
    b = a.with(amount_minor: 2)
    expect(b.amount_minor).to eq(2)
    expect(a.amount_minor).to eq(1)
    expect(b).to be_frozen
  end

  it "applies defaults" do
    ref = Navesti::AccountRef.new(iban: "EE717700771001735865")
    expect(ref.currency).to be_nil
  end

  it "deeply freezes nested raw evidence (audit immutability)" do
    acct = Navesti::Account.new(
      provider: "lhv", provider_account_id: "a-1",
      raw: { account: { "resourceId" => "a-1", "tags" => ["x"] } }
    )
    expect(acct.raw).to be_frozen
    expect(acct.raw[:account]).to be_frozen
    expect(acct.raw[:account]["tags"]).to be_frozen
    expect { acct.raw[:account]["resourceId"] = "changed" }.to raise_error(FrozenError)
  end
end
