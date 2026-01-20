import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="product-search"
// Used in the category show page modal for filtering products
export default class extends Controller {
  static targets = ["item", "input"]

  filter(event) {
    const query = event.target.value.toLowerCase().trim()

    this.itemTargets.forEach(item => {
      const name = item.dataset.name || ""
      if (query === "" || name.includes(query)) {
        item.style.display = ""
      } else {
        item.style.display = "none"
      }
    })
  }
}
