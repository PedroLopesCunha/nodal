import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="product-search"
// Used in the category show page modal for filtering products
export default class extends Controller {
  static targets = ["item"]

  connect() {
    console.log("Product search controller connected", this.itemTargets.length, "items")
  }

  filter(event) {
    const query = event.target.value.toLowerCase().trim()

    this.itemTargets.forEach(item => {
      const name = item.dataset.name || ""
      const sku = item.dataset.sku || ""
      if (query === "" || name.includes(query) || sku.includes(query)) {
        item.classList.remove("d-none")
        item.style.display = ""
      } else {
        item.classList.add("d-none")
        item.style.display = "none"
      }
    })
  }
}
