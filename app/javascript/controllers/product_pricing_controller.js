import { Controller } from "@hotwired/stimulus"

// Live pricing + unlock progress on the product page (simple products).
// On quantity change it recomputes the header price, the estimated total and
// the "X more to unlock -Y%" progress — switching to the unlocked price the
// moment the (per-line or cart-summed) threshold is reached, and celebrating it.
//
// To avoid re-implementing the discount engine in JS, the server passes two
// unit prices: lockedUnit (condition NOT met) and unlockedUnit (met). JS picks
// one based on whether the projected total reaches the threshold. `cartCurrent`
// is what's already in the cart toward the threshold (the line the page would
// merge into, or a summed product/category total).
export default class extends Controller {
  static targets = [
    "quantity", "total", "discountNote", "progress", "progressBar", "progressText",
    "celebration", "celebrationText", "headerPrice", "headerOriginal", "panelMet", "panelUnmet"
  ]
  static values = {
    lockedUnitCents: Number,
    unlockedUnitCents: Number,
    baseUnitCents: Number,
    conditionType: String, // none | quantity | amount
    threshold: Number,     // units (quantity) or cents (amount)
    cartCurrent: Number,
    discountLabel: String,
    currencySymbol: String,
    remainingTemplate: String, // "faltam %{remaining} para %{discount}"
    celebrationDefault: String,
    celebrationFromCart: String
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

    this.updateHeader(unit)
    this.updateProgress(hasCondition, met, projected)

    // "Available discounts" panel hint reflects the live state.
    if (this.hasPanelMetTarget) this.panelMetTarget.classList.toggle("d-none", !met)
    if (this.hasPanelUnmetTarget) this.panelUnmetTarget.classList.toggle("d-none", met)
  }

  updateHeader(unit) {
    if (!this.hasHeaderPriceTarget) return
    const discounted = unit < this.baseUnitCentsValue
    this.headerPriceTarget.textContent = this.formatPrice(unit)
    this.headerPriceTarget.classList.toggle("text-success", discounted)
    this.headerPriceTarget.classList.toggle("text-primary", !discounted)
    if (this.hasHeaderOriginalTarget) {
      this.headerOriginalTarget.textContent = this.formatPrice(this.baseUnitCentsValue)
      this.headerOriginalTarget.classList.toggle("d-none", !discounted)
    }
  }

  updateProgress(hasCondition, met, projected) {
    if (this.hasCelebrationTarget) {
      this.celebrationTarget.classList.toggle("d-none", !(hasCondition && met))
      if (hasCondition && met && this.hasCelebrationTextTarget) {
        // Already unlocked by what's in the cart vs. unlocked by the quantity now.
        const byCart = this.cartCurrentValue >= this.thresholdValue
        this.celebrationTextTarget.textContent = byCart ? this.celebrationFromCartValue : this.celebrationDefaultValue
      }
    }
    if (!this.hasProgressTarget) return

    const showProgress = hasCondition && !met
    this.progressTarget.classList.toggle("d-none", !showProgress)
    if (!showProgress) return

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
