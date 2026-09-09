import { Controller } from "@hotwired/stimulus"

// Choosing which companies may see stock quantities. A category is a way to
// pick everyone in it at once; what the form submits is always a list of
// companies, so reclassifying a customer later never grants access on its own.
export default class extends Controller {
  static targets = ["list", "emptyState", "search", "pickerFrame", "count", "row", "addAllButton"]

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

  // Everyone at once. The list is fetched only on the click, because "all" is
  // hundreds of companies in the larger organisations and there is no reason
  // to carry them in the page until somebody asks. It stays a snapshot, like
  // the category buttons: a company created tomorrow is not covered by this.
  addAll(event) {
    const button = event.currentTarget
    button.disabled = true

    fetch(button.dataset.url, { headers: { Accept: "application/json" } })
      .then(response => response.json())
      .then(companies => {
        // One insert instead of one per company: adding 800 rows individually
        // makes the browser lay the page out 800 times.
        const html = companies
          .filter(company => !this.hasCompany(company.id))
          .map(company => this.rowHtml(company.id, company.name, company.subtitle))
          .join("")

        if (html) this.listTarget.insertAdjacentHTML("beforeend", html)
        this.refresh()
      })
      .finally(() => { button.disabled = false })
  }

  addOne(customerId, companyName, subtitle) {
    if (this.hasCompany(customerId)) return

    this.listTarget.insertAdjacentHTML("beforeend", this.rowHtml(customerId, companyName, subtitle))
  }

  // Asked once per company being added, so it reads from a set rather than
  // walking every row each time — adding hundreds at once would otherwise cost
  // hundreds of thousands of comparisons.
  hasCompany(customerId) {
    return this.selectedIds().has(String(customerId))
  }

  selectedIds() {
    if (!this.idCache || this.idCacheSize !== this.rowTargets.length) {
      this.idCache = new Set(this.rowTargets.map(row => row.dataset.customerId))
      this.idCacheSize = this.rowTargets.length
    }
    return this.idCache
  }

  refresh() {
    const count = this.rowTargets.length
    this.idCache = null
    this.countTargets.forEach(target => { target.textContent = count })
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
