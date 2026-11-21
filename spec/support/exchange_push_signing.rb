# frozen_string_literal: true

# #1354 — signs a push the way a provider does (ExchangePushService), for the
# push specs.
module ExchangePushSigning
  def push_signature(key, connection_id:, document_source_id:, timestamp:, body:)
    message = ExchangePushService.signed_message(connection_id: connection_id, document_source_id: document_source_id,
                                                 timestamp: timestamp, body: body)
    Base64.strict_encode64(key.sign(nil, message))
  end
end

RSpec.configure { |config| config.include ExchangePushSigning }
