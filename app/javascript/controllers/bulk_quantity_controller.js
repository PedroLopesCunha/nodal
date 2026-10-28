import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit", "label"]
  static values = { label: String, unit: String, units: String }

  connect() { this.update() }

  update() {
    const count = this.inputTargets.reduce((sum, input) => sum + (input.disabled ? 0 : Math.max(0, parseInt(input.value, 10) || 0)), 0)
    this.labelTarget.textContent = this.labelValue.replace("%{count}", count).replace("%{units}", count === 1 ? this.unitValue : this.unitsValue)
    this.submitTarget.disabled = count === 0
    this.inputTargets.forEach(input => {
      input.closest("[data-grid-row]").classList.toggle("is-selected", !input.disabled && Number(input.value) > 0)
    })
  }
}
