# frozen_string_literal: true

# #1354 — pulls the documents registered on enabled connections. Hourly, it
# pulls each document whose own interval has passed (ExchangeDocumentSource#due?);
# given an id, it pulls that one document now (Pull now, and the API).
#
# One document's failure never stops the others: each is recorded on its
# source and connection and in the audit log (ExchangePullService).
#
# NIST SP 800-53: CA-7 (continuous monitoring — scheduled collection), CA-3.
class ExchangePullJob < ApplicationJob
  queue_as :default

  def perform(document_source_id = nil, user_id = nil)
    if document_source_id
      source = ExchangeDocumentSource.find_by(id: document_source_id)
      ExchangePullService.call(source, user: user_id && User.find_by(id: user_id)) if source
      return
    end

    ExchangeDocumentSource.enabled.joins(:exchange_connection).merge(ExchangeConnection.enabled)
                          .find_each do |src|
      ExchangePullService.call(src) if src.due?
    end
  end
end
