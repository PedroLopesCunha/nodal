import { Controller } from "@hotwired/stimulus"

// Toggles between product and category selects for discount targeting.
// Shows/hides the appropriate select and clears the hidden one.
export default class extends Controller {
  static targets = ["productWrapper", "categoryWrapper", "productSelect", "categorySelect"]
  static values = { url: String }

  connect() {
    this.scopeChangeHandler = () => this.scopeChanged()
    this.element.addEventListener("category-scope:change", this.scopeChangeHandler)
    this.toggle()
  }

  disconnect() {
    this.element.removeEventListener("category-scope:change", this.scopeChangeHandler)
  }

  toggle() {
    const selected = this.element.querySelector("input[name='target_type']:checked")?.value
    if (selected === "category") {
      this.productWrapperTarget.classList.add("d-none")
      this.categoryWrapperTarget.classList.remove("d-none")
      // Clear product select
      this.clearSelect(this.productSelectTarget)
    } else {
      this.productWrapperTarget.classList.remove("d-none")
      this.categoryWrapperTarget.classList.add("d-none")
      // Clear category select
      if (this.hasCategorySelectTarget) this.clearSelect(this.categorySelectTarget)
    }
    this.dispatchReload()
  }

  // Reload variant overrides when category changes
  categoryChanged() { this.dispatchReload() }

  scopeChanged() {
    if (this.element.querySelector("input[name=target_type]:checked")?.value !== "product") this.dispatchReload()
  }

  dispatchReload() {
    this.element.dispatchEvent(new CustomEvent("variant-overrides:reload", { bubbles: true }))
  }

  clearSelect(selectEl) {
    // If Tom Select is managing this element, use its API
    if (selectEl.tomselect) {
      selectEl.tomselect.clear()
    } else {
      selectEl.value = ""
    }
  }
}
