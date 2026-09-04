module Automations
  # A report is the "what" of an automation: given a period, it returns rows.
  # It knows nothing about scheduling, recipients or email — those belong to
  # Automation and Automations::Runner.
  class Base
    class << self
      # Registry key, stored in automations.kind.
      def key = raise(NotImplementedError)

      # Filter fields this report accepts. The BO form is generated from this,
      # so a new report needs no view changes.
      def filter_keys = []

      def label = I18n.t("automations.reports.#{key}.label", default: key.to_s.humanize)

      def description = I18n.t("automations.reports.#{key}.description", default: "")
    end

    attr_reader :organisation, :filters

    def initialize(organisation:, filters: {})
      @organisation = organisation
      @filters = (filters || {}).with_indifferent_access
    end

    # [{ key:, label: }, ...] — the digest table's header.
    def columns = raise(NotImplementedError)

    # [{ column_key => value, ... }, ...] for the given period.
    def rows(_period) = raise(NotImplementedError)

    def label = self.class.label
  end
end
