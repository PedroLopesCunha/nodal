import { Controller } from "@hotwired/stimulus"

// Live pricing for the bulk grid (variable product, grid add-to-cart mode).
// Rows have independent quantities. The server passes each variant's locked
// (condition unmet) and unlocked (met) unit prices.
//
// - per_line scope: each row flips to its unlocked price when its own qty
//   (+ that variant's cart line) clears the threshold.
// - summed scope: one tracker at the foot sums every row (+ the product's cart
//   total) and, once met, flips every row to its unlocked price and celebrates.
export default class extends Controller {
  static targets = [
    "rowInput", "rowPrice", "rowOriginal",
    "tracker", "trackerText", "trackerIcon", "trackerLine", "progressBar"
  ]
  static values = {
    pricing: Object,       // { [vid]: { locked, unlocked, base, cart } }
    conditionType: String, // quantity | amount
    threshold: Number,     // units or cents
    scope: String,         // per_line | summed
    cartSummed: Number,    // product/category cart total toward a summed threshold
    currencySymbol: String,
    discountLabel: String,
    remainingTemplate: String, // "faltam %{remaining} para %{discount}"
    celebration: String        // "%{discount} desbloqueado..."
  }

  connect() {
    this.update()
  }

  update() {
    if (this.scopeValue === "summed") {
      this.updateSummed()
    } else {
      this.rowInputTargets.forEach((input) => this.updatePerLineRow(input))
    }
  }

  // --- per-line: each row independent -----------------------------------
  updatePerLineRow(input) {
    const p = this.pricingFor(input)
    if (!p) return
    const qty = this.qtyOf(input)
    const contribution = this.conditionTypeValue === "amount" ? qty * p.base : qty
    const met = (p.cart || 0) + contribution >= this.thresholdValue
    this.setRowPrice(input, met ? p.unlocked : p.locked, p.base)
  }

  // --- summed: all rows share one threshold -----------------------------
  updateSummed() {
    let total = this.cartSummedValue || 0
    this.rowInputTargets.forEach((input) => {
      const p = this.pricingFor(input)
      if (!p) return
      const qty = this.qtyOf(input)
      total += this.conditionTypeValue === "amount" ? qty * p.base : qty
    })
    const met = total >= this.thresholdValue

    this.rowInputTargets.forEach((input) => {
      const p = this.pricingFor(input)
      if (p) this.setRowPrice(input, met ? p.unlocked : p.locked, p.base)
    })

    if (this.hasTrackerTarget) this.renderTracker(met, total)
  }

  renderTracker(met, total) {
    if (met) {
      this.trackerTextTarget.textContent = this.celebrationValue
      this.trackerIconTarget.className = "fa-solid fa-circle-check me-1"
      this.toggleTone(true)
      this.progressBarTarget.style.width = "100%"
    } else {
      const remaining = this.thresholdValue - total
      const remainingText = this.conditionTypeValue === "amount" ? this.formatPrice(remaining) : `${remaining}`
      this.trackerTextTarget.textContent = this.remainingTemplateValue
        .replace("%{remaining}", remainingText)
        .replace("%{discount}", this.discountLabelValue)
      this.trackerIconTarget.className = "fa-solid fa-bolt me-1"
      this.toggleTone(false)
      const pct = Math.min(Math.round((total / this.thresholdValue) * 100), 100)
      this.progressBarTarget.style.width = `${pct}%`
    }
  }

  toggleTone(met) {
    this.trackerLineTarget.classList.toggle("text-success", met)
    this.trackerLineTarget.classList.toggle("text-warning", !met)
    this.progressBarTarget.classList.toggle("bg-success", met)
    this.progressBarTarget.classList.toggle("bg-warning", !met)
  }

  // --- helpers ----------------------------------------------------------
  pricingFor(input) {
    return this.pricingValue[input.dataset.variantId]
  }

  qtyOf(input) {
    return Math.max(parseInt(input.value, 10) || 0, 0)
  }

  setRowPrice(input, unit, base) {
    const tr = input.closest("tr")
    if (!tr) return
    const priceEl = tr.querySelector("[data-grid-pricing-target='rowPrice']")
    const origEl = tr.querySelector("[data-grid-pricing-target='rowOriginal']")
    const discounted = unit < base
    if (priceEl) {
      priceEl.textContent = this.formatPrice(unit)
      priceEl.classList.toggle("text-success", discounted)
      priceEl.classList.toggle("fw-medium", discounted)
    }
    if (origEl) origEl.classList.toggle("d-none", !discounted)
  }

  formatPrice(cents) {
    return `${this.currencySymbolValue}${(cents / 100).toFixed(2)}`
  }
}
