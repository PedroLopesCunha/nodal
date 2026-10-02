import { Controller } from "@hotwired/stimulus"

// Native sticky positioning, bounded by the product table rather than the
// whole page. ResizeObserver also handles notes, quantity updates and images.
export default class extends Controller {
  static targets = ["products", "boundary", "summary"]

  connect() {
    this.update = this.update.bind(this)
    this.observer = new ResizeObserver(this.update)
    this.observer.observe(this.productsTarget)
    this.observer.observe(this.summaryTarget)
    window.addEventListener("resize", this.update, { passive: true })
    this.update()
  }

  disconnect() {
    this.observer.disconnect()
    window.removeEventListener("resize", this.update)
    this.boundaryTarget.style.removeProperty("height")
  }

  update() {
    if (window.matchMedia("(min-width: 992px)").matches) {
      this.boundaryTarget.style.height = `${Math.max(this.productsTarget.offsetHeight, this.summaryTarget.offsetHeight)}px`
    } else {
      this.boundaryTarget.style.removeProperty("height")
    }
  }
}
