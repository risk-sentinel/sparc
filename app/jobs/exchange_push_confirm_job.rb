# frozen_string_literal: true

# #1354 — confirms one push by pulling its document fresh from the registered
# address (ExchangePushConfirmService). Runs once per accepted push; a receipt
# already decided is left as it is.
#
# NIST SP 800-53: CA-3, SI-7.
class ExchangePushConfirmJob < ApplicationJob
  queue_as :default

  def perform(receipt_id)
    receipt = ExchangePushReceipt.find_by(id: receipt_id)
    ExchangePushConfirmService.call(receipt) if receipt
  end
end
