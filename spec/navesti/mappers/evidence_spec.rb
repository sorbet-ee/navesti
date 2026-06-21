# frozen_string_literal: true

# Direct contract for the shared raw-evidence wrapper (mixed into every mapper).
RSpec.describe Navesti::Mappers::Evidence do
  let(:host) { Module.new { extend Navesti::Mappers::Evidence } }

  def response(body, headers: {}, status: 200)
    FakeHTTPClient.json_response(status: status, headers: headers, body: body)
  end

  it "captures status, headers, body, and a UTC timestamp verbatim by default" do
    e = host.evidence(response({ "ok" => true }, headers: { "x-id" => "abc" }))
    expect(e[:status]).to eq(200)
    expect(e[:headers]).to include("x-id" => "abc")
    expect(e[:body]).to include("ok")
    expect(e[:captured_at]).to match(/\A\d{4}-\d{2}-\d{2}T.*(Z|\+00:00)\z/)
  end

  it "scrubs secrets from the body AND headers when redact: true" do
    r = response({ "access_token" => "SECRET-TOKEN" }, headers: { "authorization" => "Bearer SECRET-TOKEN" })
    e = host.evidence(r, redact: true)
    expect(e[:body]).not_to include("SECRET-TOKEN")
    expect(e[:headers].values.join).not_to include("SECRET-TOKEN")
  end
end
