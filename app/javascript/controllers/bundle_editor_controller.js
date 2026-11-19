import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rows", "row", "template", "summary", "total", "stock", "difference", "differenceLabel", "percentage", "error"]
  static values = { previewUrl: String, previewError: String, discountLabel: String, aboveLabel: String }

  connect() { this.schedule() }

  disconnect() {
    clearTimeout(this.previewTimer)
    this.previewRequest?.abort()
  }

  add() {
    // Rails accepts numeric indices for permitted nested attributes.
    this.nextIndex = Math.max(Date.now(), (this.nextIndex || 0) + 1)
    this.rowsTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("NEW_COMPONENT", String(this.nextIndex)))
    this.schedule()
  }

  remove(event) {
    const row = event.target.closest('[data-bundle-editor-target="row"]')
    row.querySelector('input[name$="[_destroy]"]').value = "1"
    row.querySelectorAll('select, input:not([type="hidden"])').forEach(input => { input.disabled = true })
    row.hidden = true
    row.classList.add("d-none")
    this.schedule()
  }

  schedule(event) {
    if (!this.hasSummaryTarget || !this.hasPreviewUrlValue) return
    if (event && !event.target.matches('select[name$="[product_variant_id]"], input[name$="[quantity]"], #product_price')) return
    clearTimeout(this.previewTimer)
    this.previewRequest?.abort()
    this.revision = (this.revision || 0) + 1
    const revision = this.revision
    this.summaryTarget.setAttribute("aria-busy", "true")
    this.previewTimer = setTimeout(() => this.refresh(revision), 150)
  }

  async refresh(revision) {
    const controller = new AbortController()
    this.previewRequest = controller
    const rows = [...this.rowsTarget.querySelectorAll('[data-bundle-editor-target="row"]')].filter(row => !row.hidden)
    const components = rows.map(row => ({
      product_variant_id: row.querySelector('select[name$="[product_variant_id]"]').value,
      quantity: row.querySelector('input[name$="[quantity]"]').value
    })).filter(part => part.product_variant_id)
    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST", signal: controller.signal,
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body: JSON.stringify({ components, price: this.element.querySelector("#product_price")?.value || "" })
      })
      const data = await response.json().catch(() => null)
      if (revision !== this.revision) return
      if (!response.ok || !data) {
        const error = new Error()
        error.previewMessage = data?.error || this.previewErrorValue
        throw error
      }
      this.errorTarget.classList.add("d-none")
      if (data.warning) {
        this.errorTarget.textContent = data.warning
        this.errorTarget.classList.remove("d-none")
      }
      this.totalTarget.textContent = data.total
      this.stockTarget.textContent = data.stock
      this.differenceTarget.textContent = data.difference
      this.differenceLabelTarget.textContent = data.above_base ? this.aboveLabelValue : this.discountLabelValue
      this.percentageTarget.textContent = data.percentage_label ? `(${data.percentage_label})` : ""
      rows.forEach(row => {
        const id = row.querySelector("select").value
        const line = data.lines.find(line => String(line.variant_id) === id)
        row.querySelector("[data-component-unit-price]").textContent = line?.unit_price || "—"
        row.querySelector("[data-component-stock]").textContent = line?.stock || "—"
        row.querySelector("[data-component-subtotal]").textContent = line?.subtotal || "—"
      })
    } catch (error) {
      if (error.name === "AbortError" || revision !== this.revision) return
      this.totalTarget.textContent = this.stockTarget.textContent = this.differenceTarget.textContent = "—"
      this.percentageTarget.textContent = ""
      this.errorTarget.textContent = error.previewMessage || this.previewErrorValue
      this.errorTarget.classList.remove("d-none")
    } finally {
      if (revision === this.revision) this.summaryTarget.setAttribute("aria-busy", "false")
    }
  }
}
