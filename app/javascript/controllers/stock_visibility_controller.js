import { Controller } from "@hotwired/stimulus"

// Choosing which companies may see stock quantities. A category is a way to
// pick everyone in it at once; what the form submits is always a list of
// companies, so reclassifying a customer later never grants access on its own.
export default class extends Controller {
  static targets = ["list", "emptyState", "search", "pickerFrame", "count", "row"]

  addCompany(event) {
    const { customerId, companyName, categoryName, taxpayerId } = event.currentTarget.dataset
    this.addOne(customerId, companyName, [categoryName, taxpayerId].filter(Boolean).join(" · "))
    this.refresh()
  }

  addCategory(event) {
    const ids = JSON.parse(event.currentTarget.dataset.customerIds || "[]")
    const names = JSON.parse(event.currentTarget.dataset.names || "[]")

    ids.forEach((id, index) => this.addOne(String(id), names[index] || "", ""))
    this.refresh()
  }

  remove(event) {
    event.currentTarget.closest("[data-stock-visibility-target='row']")?.remove()
    this.refresh()
  }

  addOne(customerId, companyName, subtitle) {
    if (this.hasCompany(customerId)) return

    this.listTarget.insertAdjacentHTML("beforeend", this.rowHtml(customerId, companyName, subtitle))
  }

  hasCompany(customerId) {
    return this.rowTargets.some(row => row.dataset.customerId === String(customerId))
  }

  refresh() {
    const count = this.rowTargets.length
    if (this.hasCountTarget) this.countTarget.textContent = count
    if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.toggle("d-none", count > 0)
  }

  debouncedSearch() {
    clearTimeout(this.searchTimeout)
    this.searchTimeout = setTimeout(() => this.search(), 300)
  }

  search() {
    const frame = this.pickerFrameTarget
    const url = new URL(frame.dataset.searchUrl, window.location.origin)
    const query = this.searchTarget.value.trim()

    if (query) url.searchParams.set("query", query)

    if (frame.src === url.toString()) {
      frame.reload()
    } else {
      frame.src = url.toString()
    }
  }

  // The search box sits inside the page's save form, where Enter would submit
  // it and save a half-made selection.
  preventSubmit(event) {
    event.preventDefault()
    this.search()
  }

  // Company names come from the ERP, so they are escaped rather than dropped
  // into the markup as they are.
  escape(value) {
    const div = document.createElement("div")
    div.textContent = value ?? ""
    return div.innerHTML
  }

  rowHtml(customerId, companyName, subtitle) {
    const id = this.escape(customerId)

    return `
      <div class="d-flex align-items-center gap-3 p-2 mb-2 border rounded"
           data-stock-visibility-target="row" data-customer-id="${id}">
        <input type="hidden" name="customer_ids[]" value="${id}">
        <div class="flex-grow-1">
          <strong>${this.escape(companyName)}</strong>
          <small class="text-muted d-block">${this.escape(subtitle)}</small>
        </div>
        <button type="button" class="btn btn-sm btn-link text-danger p-1"
                data-action="click->stock-visibility#remove">
          <i class="fa-solid fa-times"></i>
        </button>
      </div>
    `
  }
}
