import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.input = this.element.querySelector('input[type="number"]')
    this.sync = this.sync.bind(this)
    this.input.addEventListener("input", this.sync)
    this.observer = new MutationObserver(this.sync)
    this.observer.observe(this.input, { attributes: true, attributeFilter: ["disabled", "min", "max"] })
    this.sync()
  }

  disconnect() {
    this.input.removeEventListener("input", this.sync)
    this.observer.disconnect()
  }

  increase() { this.change(1) }
  decrease() { this.change(-1) }

  change(direction) {
    if (this.input.disabled) return
    const min = Number(this.input.min || 0)
    const step = Number(this.input.step || 1)
    const current = Number(this.input.value || 0)
    const minimum = Math.max(min, Number(this.input.dataset.minimum || min))
    let next = direction > 0 ? Math.max(minimum, current + step) : (current <= minimum ? min : current - step)
    if (this.input.max !== "") next = Math.min(next, Number(this.input.max))
    this.input.value = Math.max(min, next)
    this.input.dispatchEvent(new Event("input", { bubbles: true }))
    this.input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  sync() {
    const buttons = this.element.querySelectorAll("button")
    buttons[0].disabled = this.input.disabled || Number(this.input.value || 0) <= Number(this.input.min || 0)
    buttons[1].disabled = this.input.disabled || (this.input.max !== "" && Number(this.input.value || 0) >= Number(this.input.max))
  }
}
