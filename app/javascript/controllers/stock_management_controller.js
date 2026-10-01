import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tracking", "settings", "source", "quantity", "erpHint", "nodalHint"]

  connect() { this.refresh() }

  refresh() {
    const nodal = this.sourceTarget.value === "nodal"
    this.settingsTarget.hidden = !this.trackingTarget.checked
    this.quantityTarget.readOnly = !nodal
    this.quantityTarget.disabled = !nodal
    this.erpHintTarget.hidden = nodal
    this.nodalHintTarget.hidden = !nodal
  }
}
