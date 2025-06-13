module Navesti
  module HTTPHelpers
    def http_request(method:, url:, headers: {}, payload: nil, ssl_options: {})
      options = { method: method, url: url, headers: headers }
      options[:payload] = payload if payload
      RestClient::Request.execute(**options.merge(ssl_options))
    end

    def json_request(method:, url:, headers: {}, payload: nil, ssl_options: {})
      response = http_request(method: method, url: url, headers: headers, payload: payload, ssl_options: ssl_options)
      JSON.parse(response.body)
    end
  end

  class Step
    include HTTPHelpers
    attr_reader :name
    def initialize(name, &block)
      @name = name
      @block = block
    end
    def run(context, results)
      instance_exec(context, results, &@block)
    end
  end

  class Flow
    def initialize(name, &block)
      @name = name
      @steps = []
      instance_eval(&block) if block
    end

    def step(name, &block)
      @steps << Step.new(name, &block)
    end

    def run(context = {})
      results = {}
      @steps.each do |step|
        results[step.name] = step.run(context, results)
      end
      results
    end
  end

  def self.flow(name, &block)
    Flow.new(name, &block)
  end
end
