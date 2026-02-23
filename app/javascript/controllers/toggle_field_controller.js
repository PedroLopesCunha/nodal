import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { target: String }

  connect() {
    this.toggle()
  }

  toggle() {
    const target = document.querySelector(this.targetValue)
    if (target) {
      target.style.display = this.element.checked ? "" : "none"
    }
  }

  // Stimulus auto-wires change events on input elements
  change() {
    this.toggle()
  }
}
