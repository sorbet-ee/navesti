#!/usr/bin/env ruby
# frozen_string_literal: true

# Human-in-the-loop PIS via official Firefox (headed): initiate a SEPA payment,
# open the scaRedirect for manual sandbox SCA (PIN calculator), then poll status
# to a terminal state and save the trace.
#
# DEVELOPER TOOLING ONLY. Sandbox-gated (LHV_LIVE=1). Never headless, no iframe.
require_relative "../dev/lhv_dev"
require "time"

LhvDev.require_live!

token = ENV["LHV_ACCESS_TOKEN"] || LhvDev.read_json("token_set.json")["access_token"]
adapter = LhvDev.adapter
order = LhvDev.order_from_env

submission = adapter.initiate_sepa_payment(
  order: order,
  access_token: token,
  redirect_uri: ENV["LHV_PIS_REDIRECT_URI"] || "http://localhost:4567/lhv/pis/callback",
  nok_redirect_uri: ENV["LHV_PIS_NOK_REDIRECT_URI"]
)
payment_id = submission.provider_reference&.value
puts "paymentId: #{payment_id}  initial status: #{submission.status.raw_status} (#{submission.status.status})"

driver = nil
trace = []
record = lambda do |status|
  trace << {
    "at" => Time.now.utc.iso8601, "payment_id" => payment_id,
    "raw_status" => status.raw_status, "status" => status.status.to_s,
    "safety_status" => status.safety_status.to_s,
    "side_effect_possible" => status.side_effect_possible
  }
  LhvDev.save_json("payment_status_trace.json", trace)
end
record.call(submission.status)

begin
  if submission.interaction&.url
    driver = LhvDev.open_firefox(submission.interaction.url)
    puts "Firefox opened to scaRedirect. Complete sandbox SCA (PIN calculator, e.g. 0000)."
  else
    puts "No scaRedirect (SCA exemption?) — payment already #{submission.status.status}."
  end

  terminal = %i[confirmed rejected]
  timeout_at = Time.now + Integer(ENV["LHV_PIS_TIMEOUT"] || "300")
  loop do
    sleep Integer(ENV["LHV_PIS_POLL_INTERVAL"] || "5")
    status = adapter.payment_status(payment_id: payment_id, access_token: token)
    puts "  poll: #{status.raw_status} -> #{status.safety_status}"
    record.call(status)
    break if terminal.include?(status.safety_status)
    break if Time.now > timeout_at && (puts "  (timeout)" || true)
  end
ensure
  driver&.quit
end
puts "trace saved -> tmp/lhv/payment_status_trace.json"
