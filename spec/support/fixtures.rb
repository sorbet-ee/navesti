# frozen_string_literal: true

# Loads LHV JSON response fixtures (representative shapes copied from the LHV
# docs/Swagger, with obviously-fake values — docs/10 rule 4). Fixtures are
# verification evidence, not generated code (providers/lhv/swagger-notes.md).
module Fixtures
  DIR = File.join(__dir__, "..", "fixtures")

  module_function

  def raw(provider, name)
    File.read(File.join(DIR, provider.to_s, "#{name}.json"))
  end

  def load(provider, name)
    JSON.parse(raw(provider, name))
  end

  def lhv_response(name, status: 200)
    FakeHTTPClient.json_response(status: status, body: raw(:lhv, name))
  end

  def wise_response(name, status: 200)
    FakeHTTPClient.json_response(status: status, body: raw(:wise, name))
  end
end
