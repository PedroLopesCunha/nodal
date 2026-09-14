import { Controller } from "@hotwired/stimulus"

// The bulk invitation picker. Filters live outside the turbo frame and rebuild
// its URL; the frame brings back the list with checkboxes already ticked by the
// server. Changing a filter reloads the list, so ticks made by hand reset.
export default class extends Controller {
  static targets = ["frame", "query", "status", "sentFrom", "sentTo", "rep", "checkbox", "customerCount", "emailCount", "submit"]
  static values = { confirm: String }

  disconnect() {
    clearTimeout(this.timeout)
  }

  debouncedReload() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.reload(), 300)
  }

  // Customers not yet invited have no invitation date, so a date range only
  // makes sense for pending ones.
  statusChanged() {
    if (this.statusTarget.value === "not_invited") {
      this.sentFromTarget.value = ""
      this.sentToTarget.value = ""
    }
    this.reload()
  }

  dateChanged() {
    if (this.statusTarget.value === "not_invited") this.statusTarget.value = "pending"
    this.reload()
  }

  reload() {
    const url = new URL(this.frameTarget.dataset.url, window.location.origin)
    const params = {
      query: this.queryTarget.value.trim(),
      status: this.statusTarget.value,
      sent_from: this.sentFromTarget.value,
      sent_to: this.sentToTarget.value,
      rep: this.repTarget.value
    }
    Object.entries(params).forEach(([key, value]) => { if (value) url.searchParams.set(key, value) })

    if (this.frameTarget.src === url.toString()) {
      this.frameTarget.reload()
    } else {
      this.frameTarget.src = url.toString()
    }
  }

  // Enter in the search box would otherwise send the invitations.
  preventSubmit(event) {
    event.preventDefault()
    this.reload()
  }

  selectAll() {
    this.enabledCheckboxes().forEach(checkbox => { checkbox.checked = true })
    this.refresh()
  }

  selectNone() {
    this.enabledCheckboxes().forEach(checkbox => { checkbox.checked = false })
    this.refresh()
  }

  refresh() {
    const checked = this.checkboxTargets.filter(checkbox => checkbox.checked && !checkbox.disabled)
    const emails = checked.reduce((sum, checkbox) => sum + Number(checkbox.dataset.emails || 0), 0)

    this.customerCountTarget.textContent = checked.length
    this.emailCountTarget.textContent = emails
    this.submitTarget.disabled = checked.length === 0
  }

  enabledCheckboxes() {
    return this.checkboxTargets.filter(checkbox => !checkbox.disabled)
  }

  confirmSubmit(event) {
    const emails = this.emailCountTarget.textContent
    const message = this.confirmValue.replace("__EMAILS__", emails)
    if (!window.confirm(message)) event.preventDefault()
  }
}
