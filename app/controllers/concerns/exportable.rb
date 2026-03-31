module Exportable
  extend ActiveSupport::Concern

  def export
    authorize exportable_class, :export?

    columns = exportable_class.exportable_columns_for(params[:columns])
    format = params[:format_type] || "csv"
    extension = format == "xlsx" ? "xlsx" : "csv"

    records = apply_export_filters(exportable_base_scope)
    result = ExportService.new(records: records, columns: columns, format: format).call

    filename = "#{exportable_class.model_name.plural}_#{Date.today.iso8601}.#{extension}"
    send_data result[:data], filename: filename, type: result[:content_type], disposition: "attachment"
  end
end
