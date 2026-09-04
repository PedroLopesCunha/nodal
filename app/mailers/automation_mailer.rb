class AutomationMailer < ApplicationMailer
  include OrgEmailDefaults

  helper :application

  # Generic digest: the table is driven by the report's `columns`, so a new
  # automation type needs no new template.
  #
  # Deliberately link-free. Recipients can be external (a supplier, a rep's
  # personal address) and have no BO login — a "view in Nodal" button would
  # dead-end on a sign-in screen. The email carries the whole table instead.
  def digest
    @automation   = params[:automation]
    @organisation = params[:organisation]
    @columns      = params[:columns]
    @rows         = params[:rows]
    @period       = params[:period]
    recipients    = params[:recipients]

    unless EmailDeliveryGuard.should_send?(organisation: @organisation, email_type: "automation_digest")
      log_skipped(@organisation, "automation_digest", recipients.join(", "))
      return
    end

    I18n.with_locale(@organisation.default_locale) do
      subject = t("mailers.automation_mailer.digest.subject",
                  name: @automation.name,
                  count: @rows.size)

      # bcc, not to: external recipients must not see each other's addresses,
      # and a supplier has no business reading the internal distribution list.
      mail_with_org_defaults(
        @organisation,
        to: @organisation.email_from_address,
        bcc: recipients,
        subject: subject
      )
    end
  end

  private

  def logged_email_type = "automation_digest"
end
