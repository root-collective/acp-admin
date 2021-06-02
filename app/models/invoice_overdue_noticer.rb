class InvoiceOverdueNoticer
  DAYS_DELAY = 35.days.freeze
  attr_reader :invoice

  def self.perform(*args)
    new(*args).perform
  end

  def initialize(invoice)
    @invoice = invoice
  end

  def perform
    return unless overdue_noticable?

    invoice.increment(:overdue_notices_count)
    invoice.overdue_notice_sent_at = Time.current
    invoice.save!

    MailTemplate.deliver_later(:invoice_overdue_notice, invoice: invoice)
  rescue => e
    ExceptionNotifier.notify(e,
      invoice_id: invoice.id,
      emails: invoice.member.emails,
      member_id: invoice.member_id)
    Sentry.capture_exception(e, extra: {
      invoice_id: invoice.id,
      emails: invoice.member.emails,
      member_id: invoice.member_id
    })
  end

  private

  def overdue_noticable?
    invoice.open? && last_sent_at < DAYS_DELAY.ago && member_emails?
  end

  def member_emails?
    invoice.member.emails?
  end

  def last_sent_at
    invoice.overdue_notice_sent_at || invoice.sent_at
  end
end
