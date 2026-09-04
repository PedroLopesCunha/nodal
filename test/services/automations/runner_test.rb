require "test_helper"

module Automations
  class RunnerTest < ActiveSupport::TestCase
    setup do
      @organisation = Organisation.create!(
        name: "Test Org",
        slug: "test-org-#{SecureRandom.hex(4)}",
        currency: "EUR",
        tax_rate: 0.23,
        timezone: "Europe/Lisbon",
        low_stock_threshold: 5
      )
      @automation = Automation.create!(
        organisation: @organisation,
        name: "Rupturas semanais",
        kind: "out_of_stock_digest",
        schedule_kind: "weekly",
        schedule_day: 5,
        schedule_hour: 9,
        recipients: { "external_emails" => [ "fornecedor@exemplo.pt" ] }
      )
    end

    def variant_with_rupture(occurred_at: 1.day.ago, supplier: nil)
      product = Product.create!(
        organisation: @organisation,
        name: "Product #{SecureRandom.hex(4)}",
        slug: "product-#{SecureRandom.hex(4)}",
        unit_price: 1000,
        supplier: supplier
      )
      variant = product.default_variant
      variant.update!(sku: "SKU-#{SecureRandom.hex(3)}")

      StockEvent.create!(
        organisation: @organisation,
        product_variant: variant,
        kind: StockEvent::OUT_OF_STOCK,
        from_quantity: 4,
        to_quantity: 0,
        occurred_at: occurred_at
      )
      variant
    end

    test "a run with rows sends one email and completes" do
      variant_with_rupture

      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        run = Runner.new(@automation).call
        assert_equal AutomationRun::COMPLETED, run.status
        assert_equal 1, run.rows_count
        assert_equal 1, run.recipients_count
      end
    end

    test "external recipients go in bcc so they never see each other" do
      variant_with_rupture
      @automation.update!(recipients: { "external_emails" => [ "a@exemplo.pt", "b@exemplo.pt" ] })

      Runner.new(@automation).call

      mail = ActionMailer::Base.deliveries.last
      assert_equal [ "a@exemplo.pt", "b@exemplo.pt" ], mail.bcc
      assert_not_includes Array(mail.to), "a@exemplo.pt"
    end

    test "an empty period is skipped when skip_if_empty is set" do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        run = Runner.new(@automation).call
        assert_equal AutomationRun::SKIPPED, run.status
        assert_equal 0, run.rows_count
      end
    end

    test "an empty period still sends when skip_if_empty is off" do
      @automation.update!(skip_if_empty: false)

      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        assert_equal AutomationRun::COMPLETED, Runner.new(@automation).call.status
      end
    end

    test "a run with no reachable recipients is skipped, not failed" do
      variant_with_rupture
      # Points at a member that doesn't exist — the address list resolves empty.
      @automation.update_column(:recipients, { "org_member_ids" => [ 999_999 ], "external_emails" => [] })

      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        assert_equal AutomationRun::SKIPPED, Runner.new(@automation.reload).call.status
      end
    end

    test "a scheduled run advances the schedule cursor" do
      variant_with_rupture
      # What the dispatcher sees: the automation has come due.
      @automation.update_column(:next_run_at, 1.minute.ago)
      before = @automation.reload.next_run_at

      Runner.new(@automation).call

      @automation.reload
      assert_not_nil @automation.last_run_at
      assert @automation.next_run_at > before
    end

    test "a manual run sends but does not move the schedule" do
      variant_with_rupture
      before = @automation.next_run_at

      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        run = Runner.new(@automation).call(manual: true)
        assert run.manual?
      end

      @automation.reload
      assert_nil @automation.last_run_at, "a test send must not eat the next digest's period"
      assert_equal before.to_i, @automation.next_run_at.to_i
    end

    test "the period only covers events since the last run" do
      variant_with_rupture(occurred_at: 10.days.ago)
      variant_with_rupture(occurred_at: 1.day.ago)
      @automation.update_column(:last_run_at, 3.days.ago)

      run = Runner.new(@automation.reload).call
      assert_equal 1, run.rows_count, "the 10-day-old rupture belongs to an earlier digest"
    end

    test "a failing report is recorded as failed and still advances the schedule" do
      variant_with_rupture
      @automation.update_columns(kind: "gone_missing", next_run_at: 1.minute.ago)
      before = @automation.reload.next_run_at

      run = Runner.new(@automation.reload).call

      assert_equal AutomationRun::FAILED, run.status
      assert_match(/gone_missing/, run.error_message)
      assert @automation.reload.next_run_at > before,
             "a broken automation must not be retried every 15 minutes forever"
    end

    test "the table header follows the organisation locale, not the ambient one" do
      @organisation.update!(default_locale: "pt")
      variant_with_rupture

      I18n.with_locale(:en) do
        Runner.new(@automation).call
      end

      body = ActionMailer::Base.deliveries.last.html_part.body.to_s
      assert_match "Referência", body, "column labels must render in the org's language"
      assert_no_match(/Stock before/, body)
    end

    test "the org email toggle suppresses delivery and logs it as skipped" do
      variant_with_rupture
      @organisation.update!(email_automation_enabled: false)

      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        Runner.new(@automation).call
      end
      assert_equal "skipped", EmailLog.last.status
      assert_equal "automation_digest", EmailLog.last.email_type
    end
  end
end
