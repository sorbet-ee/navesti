# frozen_string_literal: true

# Direct contract for the shared adapter error guard, independent of any
# provider. Each adapter supplies #provider_label and #provider_error_code; the
# guard turns failed responses into typed, redaction-safe errors.
RSpec.describe Navesti::Adapters::ErrorGuard do
  # A minimal adapter-like host. `error_envelope` selects the OBIE (Errors[]) or
  # Berlin Group (tppMessages) code extraction, mirroring the real hooks.
  def guarded(label: "Bank", envelope: :obie)
    Class.new do
      include Navesti::Adapters::ErrorGuard
      def initialize(label, env)
        @label = label
        @env = env
      end

      def provider_label = @label

      def provider_error_code(body)
        case @env
        when :obie   then Array(body["Errors"]).find { |e| e.is_a?(Hash) && e["ErrorCode"] }&.dig("ErrorCode")
        when :berlin then (body["tppMessages"] || []).find { |m| m["category"] == "ERROR" }&.dig("code")
        end
      end
    end.new(label, envelope)
  end

  def response(status, body)
    FakeHTTPClient.json_response(status: status, body: body)
  end

  describe "#guard_response! (AIS/PIS)" do
    it "returns without raising on a 2xx" do
      expect(guarded.guard_response!(response(200, { "ok" => true }))).to be_nil
    end

    it "maps 401 to ConsentError (host re-supplies credentials)" do
      expect { guarded(label: "Wise").guard_response!(response(401, {})) }
        .to raise_error(Navesti::ConsentError, "Wise rejected the access token (HTTP 401)")
    end

    it "raises ProviderError with the in-body provider code on other failures" do
      expect { guarded(label: "Wise").guard_response!(response(403, { "Errors" => [{ "ErrorCode" => "UK.OBIE.Resource.Forbidden" }] })) }
        .to raise_error(Navesti::ProviderError) { |e|
          expect(e.message).to eq("Wise error UK.OBIE.Resource.Forbidden (HTTP 403)")
          expect(e.provider_code).to eq("UK.OBIE.Resource.Forbidden")
          expect(e.http_status).to eq(403)
        }
    end
  end

  describe "#guard_oauth_response! (token endpoint)" do
    it "surfaces an OAuth error on 401 rather than masking it as ConsentError" do
      expect { guarded(label: "Revolut").guard_oauth_response!(response(401, { "error" => "invalid_client" })) }
        .to raise_error(Navesti::ProviderError, "Revolut OAuth error invalid_client (HTTP 401)")
    end

    it "falls back to a generic ProviderError when the body has no code or error" do
      expect { guarded(label: "LHV").guard_oauth_response!(response(500, { "noise" => 1 })) }
        .to raise_error(Navesti::ProviderError, "LHV request failed (HTTP 500)")
    end
  end

  describe "code extraction is pluggable per envelope" do
    it "reads the Berlin Group tppMessages code" do
      expect { guarded(label: "LHV", envelope: :berlin).guard_response!(response(400, { "tppMessages" => [{ "category" => "ERROR", "code" => "FORMAT_ERROR" }] })) }
        .to raise_error(Navesti::ProviderError, "LHV error FORMAT_ERROR (HTTP 400)")
    end

    # Documented, accepted behavior (reviewed 2026-06): an ERROR entry with NO
    # code is unreachable for Berlin Group (code is required) and falls through
    # to the generic message rather than emitting a blank "error " code.
    it "falls through to generic when an ERROR entry carries no code" do
      expect { guarded(label: "LHV", envelope: :berlin).guard_response!(response(400, { "tppMessages" => [{ "category" => "ERROR" }] })) }
        .to raise_error(Navesti::ProviderError, "LHV request failed (HTTP 400)")
    end
  end
end
