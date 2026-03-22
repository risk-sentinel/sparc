class ApplicationMailer < ActionMailer::Base
  default from: -> { SparcConfig.smtp_from_address || "noreply@sparc.local" }
  layout "mailer"
end
