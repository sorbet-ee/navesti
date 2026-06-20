# frozen_string_literal: true

# A test double for Navesti::HTTP::Client. Returns queued canned responses and
# records the requests it received, so specs can assert on headers, URLs, and
# bodies without any network. An enqueued Exception is raised instead of
# returned (to simulate transport failures).
class FakeHTTPClient
  attr_reader :requests

  def initialize(*responses)
    @responses = responses.flatten
    @requests = []
  end

  def request(**kwargs)
    @requests << kwargs
    nextone = @responses.shift
    raise "FakeHTTPClient: no more queued responses" if nextone.nil?
    raise nextone if nextone.is_a?(Exception)

    nextone
  end

  def last_request
    @requests.last
  end

  # Builds a Navesti::HTTP::Response from a status + JSON-able hash/string.
  def self.json_response(status: 200, headers: {}, body:)
    Navesti::HTTP::Response.new(
      status: status,
      headers: { "content-type" => "application/json" }.merge(headers),
      body: body.is_a?(String) ? body : JSON.generate(body)
    )
  end
end
