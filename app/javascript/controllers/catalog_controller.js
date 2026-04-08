import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "searchInput", "categoryItem", "productItem",
    "categoryCount", "productCount",
    "settingsCategoryCount", "settingsProductCount",
    "hiddenFields"
  ]

  connect() {
    this.selectedCategories = new Set()
    this.selectedProducts = new Set()
    this.updateCounts()
  }

  normalize(str) {
    return (str || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
  }

  // Search
  search() {
    const query = this.normalize(this.searchInputTarget.value.trim())
    this.categoryItemTargets.forEach(item => {
      const name = this.normalize(item.dataset.name)
      const match = !query || name.includes(query)
      item.style.display = match ? "" : "none"
      // Also show if any child product matches
      if (!match) {
        const products = item.querySelectorAll("[data-catalog-target='productItem']")
        let childMatch = false
        products.forEach(p => {
          const pName = this.normalize(p.dataset.name)
          const pSku = this.normalize(p.dataset.sku)
          const pVariantSkus = this.normalize(p.dataset.variantSkus)
          const pCategory = this.normalize(p.dataset.category)
          if (pName.includes(query) || pSku.includes(query) || pVariantSkus.includes(query) || pCategory.includes(query)) childMatch = true
        })
        if (childMatch) item.style.display = ""
      }
    })

    // Search standalone product items too
    this.productItemTargets.forEach(item => {
      if (item.closest("[data-catalog-target='categoryItem']")) return // handled above
      const name = this.normalize(item.dataset.name)
      const sku = this.normalize(item.dataset.sku)
      const variantSkus = this.normalize(item.dataset.variantSkus)
      const category = this.normalize(item.dataset.category)
      item.style.display = (!query || name.includes(query) || sku.includes(query) || variantSkus.includes(query) || category.includes(query)) ? "" : "none"
    })
  }

  // Toggle category expand/collapse
  toggleExpand(event) {
    event.preventDefault()
    const container = event.currentTarget.closest("[data-catalog-target='categoryItem']")
    const children = container.querySelector(".category-children")
    const icon = event.currentTarget.querySelector("i")
    if (children) {
      children.classList.toggle("d-none")
      icon.classList.toggle("fa-chevron-right")
      icon.classList.toggle("fa-chevron-down")
    }
  }

  // Toggle category selection
  toggleCategory(event) {
    const checkbox = event.currentTarget
    const categoryId = checkbox.value
    const container = checkbox.closest("[data-catalog-target='categoryItem']")

    if (checkbox.checked) {
      this.selectedCategories.add(categoryId)
      // Check all product children
      container.querySelectorAll(".product-checkbox").forEach(cb => {
        cb.checked = true
        this.selectedProducts.add(cb.value)
      })
    } else {
      this.selectedCategories.delete(categoryId)
      // Uncheck all product children
      container.querySelectorAll(".product-checkbox").forEach(cb => {
        cb.checked = false
        this.selectedProducts.delete(cb.value)
      })
    }
    this.updateCounts()
  }

  // Toggle individual product
  toggleProduct(event) {
    const checkbox = event.currentTarget
    const productId = checkbox.value

    if (checkbox.checked) {
      this.selectedProducts.add(productId)
    } else {
      this.selectedProducts.delete(productId)
      // Uncheck parent category if a product is unchecked
      const categoryItem = checkbox.closest("[data-catalog-target='categoryItem']")
      if (categoryItem) {
        const catCheckbox = categoryItem.querySelector(".category-checkbox")
        if (catCheckbox) catCheckbox.checked = false
        this.selectedCategories.delete(catCheckbox?.value)
      }
    }
    this.updateCounts()
  }

  // Select all visible
  selectAll(event) {
    event.preventDefault()
    this.categoryItemTargets.forEach(item => {
      if (item.style.display === "none") return
      const cb = item.querySelector(".category-checkbox")
      if (cb) { cb.checked = true; this.selectedCategories.add(cb.value) }
      item.querySelectorAll(".product-checkbox").forEach(pcb => {
        pcb.checked = true
        this.selectedProducts.add(pcb.value)
      })
    })
    this.updateCounts()
  }

  // Deselect all
  deselectAll(event) {
    event.preventDefault()
    this.selectedCategories.clear()
    this.selectedProducts.clear()
    document.querySelectorAll(".category-checkbox, .product-checkbox").forEach(cb => cb.checked = false)
    this.updateCounts()
  }

  updateCounts() {
    const catCount = this.selectedCategories.size
    const prodCount = this.selectedProducts.size

    // Update in selection modal
    if (this.hasCategoryCountTarget) this.categoryCountTarget.textContent = catCount
    if (this.hasProductCountTarget) this.productCountTarget.textContent = prodCount

    // Update in settings modal
    if (this.hasSettingsCategoryCountTarget) this.settingsCategoryCountTarget.textContent = catCount
    if (this.hasSettingsProductCountTarget) this.settingsProductCountTarget.textContent = prodCount

    // Update hidden fields
    if (this.hasHiddenFieldsTarget) {
      const container = this.hiddenFieldsTarget
      container.innerHTML = ""
      this.selectedProducts.forEach(id => {
        const input = document.createElement("input")
        input.type = "hidden"
        input.name = "product_ids[]"
        input.value = id
        container.appendChild(input)
      })
      this.selectedCategories.forEach(id => {
        const input = document.createElement("input")
        input.type = "hidden"
        input.name = "catalog_category_ids[]"
        input.value = id
        container.appendChild(input)
      })
    }
  }

  // Called when closing selection modal - go back to settings
  doneSelecting() {
    const selectionModal = bootstrap.Modal.getInstance(document.getElementById("catalogSelectionModal"))
    if (selectionModal) selectionModal.hide()
    // Small delay to let modal close animation finish
    setTimeout(() => {
      const settingsModal = bootstrap.Modal.getOrCreateInstance(document.getElementById("catalogModal"))
      settingsModal.show()
    }, 300)
  }

  // Open selection modal from settings modal
  openSelection(event) {
    event.preventDefault()
    const settingsModal = bootstrap.Modal.getInstance(document.getElementById("catalogModal"))
    if (settingsModal) settingsModal.hide()
    setTimeout(() => {
      const selectionModal = bootstrap.Modal.getOrCreateInstance(document.getElementById("catalogSelectionModal"))
      selectionModal.show()
    }, 300)
  }
}
