import { Controller } from "@hotwired/stimulus"

// Live pricing + unlock progress on the product page (simple products).
// On quantity change, recomputes the estimated total — applying the nearest
// conditional discount only when its (per-line or cart-summed) threshold is
// reached — and updates the "X more to unlock -Y%" progress bar.
//
// To avoid re-implementing the discount engine in JS, the server passes two
// unit prices: lockedUnit (condition NOT met) and unlockedUnit (met). JS just
// picks one based on whether the projected total reaches the threshold.
export default class extends Controller {
  static targets = ["quantity", "total", "discountNote", "progress", "progressBar", "progressText"]
  static values = {
    lockedUnitCents: Number,
    unlockedUnitCents: Number,
    baseUnitCents: Number,
    conditionType: String, // none | quantity | amount
    threshold: Number,     // units (quantity) or cents (amount)
    cartCurrent: Number,   // already in cart toward a summed threshold, else 0
    discountLabel: String,
    currencySymbol: String,
    remainingTemplate: String // "faltam %{remaining} para %{discount}"
  }

  connect() {
    this.update()
  }

  update() {
    const qty = Math.max(parseInt(this.quantityTarget.value, 10) || 0, 0)
    const hasCondition = this.conditionTypeValue !== "none" && this.thresholdValue > 0
    const contribution = this.conditionTypeValue === "amount" ? qty * this.baseUnitCentsValue : qty
    const projected = this.cartCurrentValue + contribution
    const met = !hasCondition || projected >= this.thresholdValue

    const unit = met ? this.unlockedUnitCentsValue : this.lockedUnitCentsValue
    if (this.hasTotalTarget) this.totalTarget.textContent = this.formatPrice(unit * qty)
    if (this.hasDiscountNoteTarget) {
      this.discountNoteTarget.textContent = met && hasCondition ? `(${this.discountLabelValue})` : ""
    }

    if (!this.hasProgressTarget) return
    if (!hasCondition || met) {
      this.progressTarget.classList.add("d-none")
      return
    }
    this.progressTarget.classList.remove("d-none")

    const remaining = this.thresholdValue - projected
    const remainingText = this.conditionTypeValue === "amount" ? this.formatPrice(remaining) : `${remaining}`
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = this.remainingTemplateValue
        .replace("%{remaining}", remainingText)
        .replace("%{discount}", this.discountLabelValue)
    }
    if (this.hasProgressBarTarget) {
      const pct = Math.min(Math.round((projected / this.thresholdValue) * 100), 100)
      this.progressBarTarget.style.width = `${pct}%`
    }
  }

  formatPrice(cents) {
    return `${this.currencySymbolValue}${(cents / 100).toFixed(2)}`
  }
}
