# frozen_string_literal: true

# Shared helpers for the LHV developer CLI scripts (bin/navesti-lhv-*) and the
# browser harness (tools/browser/*). DEVELOPER TOOLING ONLY — this file is not
# part of the gem (lib/) and is never required by it.
#
# Honors the CLAUDE.md browser/security rules: live calls are gated behind
# LHV_LIVE=1, secrets are never logged, token sets are chmod 600, artifacts go
# to gitignored tmp/lhv/.

require "json"
require "socket"
require "securerandom"
require "uri"
require "fileutils"
require "tmpdir"
require "time"

module LhvDev
  PROJECT_ROOT = File.expand_path("../..", __dir__)
  LIB_DIR      = File.join(PROJECT_ROOT, "lib")
  TMP_DIR      = File.join(PROJECT_ROOT, "tmp", "lhv")
  DEFAULT_REDIRECT_URI = "http://localhost:4567/lhv/oauth/callback"
  CALLBACK_PATH = "/lhv/oauth/callback"

  module_function

  # Loads the Navesti gem from source (no bundler needed — stdlib-only runtime).
  def boot
    $LOAD_PATH.unshift(LIB_DIR) unless $LOAD_PATH.include?(LIB_DIR)
    require "navesti"
  end

  # Live network calls must be explicitly enabled. Prints the exact refusal
  # message and exits otherwise.
  def require_live!
    return if ENV["LHV_LIVE"] == "1"

    abort "Refusing live LHV call. Set LHV_LIVE=1."
  end

  def env(name)
    value = ENV[name]
    abort "Missing required env var: #{name}" if value.nil? || value.empty?
    value
  end

  def credentials
    boot
    Navesti::Credentials.from_env
  rescue KeyError => e
    abort "Missing credential env var (#{e.message}). See .env.example."
  end

  def adapter(environment: :sandbox)
    boot
    Navesti.adapter(:lhv, credentials: credentials, env: environment)
  end

  def redirect_uri
    ENV["LHV_REDIRECT_URI"] || DEFAULT_REDIRECT_URI
  end

  # --- artifacts (tmp/lhv, gitignored) ---

  def tmp_path(name)
    FileUtils.mkdir_p(TMP_DIR)
    File.join(TMP_DIR, name)
  end

  # Writes a JSON artifact. secret: true → chmod 600 (token sets, codes).
  def save_json(name, data, secret: false)
    path = tmp_path(name)
    File.write(path, JSON.pretty_generate(data))
    File.chmod(0o600, path) if secret
    path
  end

  def read_json(name)
    path = tmp_path(name)
    abort "Missing #{path}. Run the earlier step first." unless File.file?(path)

    JSON.parse(File.read(path))
  end

  # Routes any string through the gem's redaction before printing.
  def scrub(string)
    boot
    Navesti::Redaction.scrub(string.to_s)
  end

  def say(message)
    puts scrub(message)
  end

  # Builds a PaymentOrder from env, with sandbox defaults (Liis-Mari -> Donald).
  def order_from_env
    boot
    Navesti::PaymentOrder.new(
      money: Navesti::Money.new(
        amount_minor: Integer(ENV["LHV_AMOUNT_MINOR"] || "100"),
        currency: ENV["LHV_CURRENCY"] || "EUR"
      ),
      debtor: Navesti::AccountRef.iban(ENV["LHV_DEBTOR_IBAN"] || "EE717700771001735865"),
      creditor: Navesti::AccountRef.iban(ENV["LHV_CREDITOR_IBAN"] || "EE857700771001735904"),
      creditor_name: ENV["LHV_CREDITOR_NAME"] || "Donald Duck",
      remittance_information: ENV["LHV_REMITTANCE"] || "navesti dev flow",
      idempotency_key: "dev-#{SecureRandom.hex(6)}"
    )
  end

  # --- minimal stdlib OAuth callback server (no WEBrick dependency) ---
  #
  # Listens on localhost for the redirect_uri callback, captures code+state from
  # the query string, returns a plain "you may close this window" page, and
  # validates state. Single-shot: serves until it sees the callback path.
  class CallbackServer
    def initialize(redirect_uri)
      uri = URI.parse(redirect_uri)
      @host = uri.host
      @port = uri.port
      @path = uri.path
      @server = TCPServer.new(@host, @port)
    end

    attr_reader :host, :port

    # Blocks until the callback is hit or +timeout+ seconds pass. Returns a hash
    # { "code" => ..., "state" => ... } or nil on timeout.
    def wait_for_callback(timeout: 300)
      deadline = Time.now + timeout
      loop do
        return nil if Time.now > deadline

        ready = IO.select([@server], nil, nil, 1)
        next unless ready

        client = @server.accept
        request_line = client.gets.to_s
        params = parse_query(request_line)
        respond(client, params)
        client.close

        # Ignore favicon and other noise; only return on the callback path.
        return params if request_line.include?(@path)
      end
    ensure
      # caller calls #close
    end

    def close
      @server.close unless @server.closed?
    end

    private

    def parse_query(request_line)
      # "GET /lhv/oauth/callback?code=..&state=.. HTTP/1.1"
      target = request_line.split(" ")[1].to_s
      query = target.split("?", 2)[1].to_s
      URI.decode_www_form(query).to_h
    rescue StandardError
      {}
    end

    def respond(client, params)
      ok = params["code"] && !params["code"].empty?
      title = ok ? "Authorization received" : "Waiting for authorization"
      body = "<html><body style='font-family:sans-serif'>" \
             "<h2>#{title}</h2><p>You may close this window and return to the terminal.</p>" \
             "</body></html>"
      client.print "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n" \
                   "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    end
  end

  # Runs the OAuth callback capture: builds the URL, starts the server, yields
  # the URL to a block (which opens a browser or prints it), waits, validates
  # state, and persists the code. Returns the captured code string.
  def capture_oauth_code(timeout: 300)
    require_live!
    a = adapter
    state = "navesti-#{SecureRandom.hex(8)}"
    interaction = a.authorize_url(redirect_uri: redirect_uri, state: state)

    server = CallbackServer.new(redirect_uri)
    begin
      yield(interaction.url, state)
      say "Waiting for the bank redirect on #{redirect_uri} (timeout #{timeout}s)..."
      params = server.wait_for_callback(timeout: timeout)
      abort "Timed out waiting for the OAuth callback." if params.nil?
      abort "State mismatch — possible CSRF; aborting." unless params["state"] == state
      abort "No authorization code in callback." if params["code"].to_s.empty?

      save_json("oauth_code.json", { "captured_at" => Time.now.utc.iso8601 }.merge(params), secret: true)
      say "Authorization code captured -> tmp/lhv/oauth_code.json"
      params["code"]
    ensure
      server.close
    end
  end

  # --- Firefox (headed, official, temp profile) via Selenium, opt-in ---

  def require_selenium!
    require "selenium-webdriver"
  rescue LoadError
    abort <<~MSG
      The browser harness needs selenium-webdriver (NOT a gem dependency — dev only).
      Install it and a driver, then retry:
        gem install selenium-webdriver
        brew install geckodriver         # or ensure geckodriver is on PATH
      Official Firefox must be installed. Headed mode only; never headless for bank SCA.
    MSG
  end

  # Opens a headed Firefox with a dedicated temporary profile at +url+ and
  # returns the driver. Never headless (CLAUDE.md browser rule 2).
  def open_firefox(url)
    require_selenium!
    profile_dir = Dir.mktmpdir("navesti-firefox-")
    options = Selenium::WebDriver::Firefox::Options.new
    options.add_argument("-profile")
    options.add_argument(profile_dir)
    # Headed only — do NOT add "-headless".
    driver = Selenium::WebDriver.for(:firefox, options: options)
    driver.navigate.to(url)
    driver
  end
end
