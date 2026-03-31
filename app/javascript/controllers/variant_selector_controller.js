import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "variantId", "price", "originalPrice", "sku", "stock", "addToCart", "image", "zoomImage", "mainPrice", "discountBadge", "quantity"]
  static values = {
    variants: Array,
    currencySymbol: String,
    defaultPriceCents: Number,
    defaultFinalPriceCents: Number,
    defaultHasDiscount: Boolean,
    defaultDiscountPercentage: Number,
    minQuantity: Number,
    defaultSku: String,
    inStockText: { type: String, default: "In Stock" },
    outOfStockText: { type: String, default: "Out of Stock" },
    displayPrice: { type: String, default: "" }
  }

  connect() {
    this.selectedVariant = null
    this.originalImageUrl = this.hasImageTarget ? this.imageTarget.src : null
    // Store all original options per select for filtering
    this.originalOptions = this.selectTargets.map(select => {
      return Array.from(select.options).map(opt => ({
        value: opt.value,
        text: opt.textContent,
        selected: opt.selected,
        color: opt.dataset.color
      }))
    })
    this.filterAvailableOptions()
    this.updateSelection()
    this.updateTotal()
  }

  change() {
    this.filterAvailableOptions()
    this.updateSelection()
    this.updateTotal()
  }

  filterAvailableOptions() {
    const selects = this.selectTargets.filter(s => !s.classList.contains("d-none"))

    selects.forEach((currentSelect, currentIndex) => {
      // Get selected values from ALL OTHER selects (not this one)
      const otherSelections = []
      selects.forEach((otherSelect, otherIndex) => {
        if (otherIndex !== currentIndex && otherSelect.value) {
          otherSelections.push(parseInt(otherSelect.value))
        }
      })

      // Find which values for THIS select's attribute are compatible
      // with the other selections
      const compatibleValueIds = new Set()

      this.variantsValue.forEach(variant => {
        // Check if this variant matches all other selections
        const matchesOthers = otherSelections.every(selectedId =>
          variant.attribute_value_ids.includes(selectedId)
        )

        if (matchesOthers) {
          // This variant is compatible — its attribute values for this select are valid
          const originalValueIds = this.originalOptions[this.selectTargets.indexOf(currentSelect)]
            .filter(opt => opt.value)
            .map(opt => parseInt(opt.value))

          variant.attribute_value_ids.forEach(valueId => {
            if (originalValueIds.includes(valueId)) {
              compatibleValueIds.add(valueId)
            }
          })
        }
      })

      // Update the options: disable incompatible ones
      const currentValue = currentSelect.value
      Array.from(currentSelect.options).forEach(option => {
        if (!option.value) return // Skip placeholder
        const valueId = parseInt(option.value)
        const isCompatible = compatibleValueIds.has(valueId)
        option.disabled = !isCompatible
        option.style.display = isCompatible ? "" : "none"
      })

      // If current selection is no longer compatible, reset to first compatible
      if (currentValue && !compatibleValueIds.has(parseInt(currentValue))) {
        const firstCompatible = Array.from(currentSelect.options).find(
          opt => opt.value && !opt.disabled
        )
        currentSelect.value = firstCompatible ? firstCompatible.value : ""
      }
    })
  }

  updateTotal() {
    const quantity = this.hasQuantityTarget ? parseInt(this.quantityTarget.value) || this.minQuantityValue || 1 : this.minQuantityValue || 1

    let priceCents
    if (this.selectedVariant) {
      priceCents = this.selectedVariant.has_discount ? this.selectedVariant.final_price_cents : this.selectedVariant.price_cents
    } else {
      priceCents = this.defaultHasDiscountValue ? this.defaultFinalPriceCentsValue : this.defaultPriceCentsValue
    }

    if (priceCents && this.hasPriceTarget) {
      const total = priceCents * quantity
      this.priceTarget.textContent = this.formatPrice(total)
    }
  }

  updateSelection() {
    const selectedValues = this.getSelectedValues()
    const variant = this.findMatchingVariant(selectedValues)

    if (variant) {
      this.selectedVariant = variant
      this.updateDisplay(variant)
      this.updateMainPrice(variant)
      this.enableAddToCart(variant)
    } else {
      this.selectedVariant = null
      this.showPriceRange()
      this.disableAddToCart()
    }
  }

  updateMainPrice(variant) {
    if (!this.hasMainPriceTarget || !variant) return

    if (variant.has_discount) {
      this.mainPriceTarget.textContent = this.formatPrice(variant.final_price_cents)
      this.mainPriceTarget.classList.remove("text-primary")
      this.mainPriceTarget.classList.add("text-success")

      if (this.hasOriginalPriceTarget) {
        this.originalPriceTarget.textContent = this.formatPrice(variant.price_cents)
        this.originalPriceTarget.classList.remove("d-none")
      }

      if (this.hasDiscountBadgeTarget) {
        this.discountBadgeTarget.textContent = `-${variant.discount_percentage}% OFF`
        this.discountBadgeTarget.classList.remove("d-none")
      }
    } else {
      this.mainPriceTarget.textContent = this.formatPrice(variant.price_cents)
      this.mainPriceTarget.classList.remove("text-success")
      this.mainPriceTarget.classList.add("text-primary")

      if (this.hasOriginalPriceTarget) {
        this.originalPriceTarget.classList.add("d-none")
      }
      if (this.hasDiscountBadgeTarget) {
        this.discountBadgeTarget.classList.add("d-none")
      }
    }
  }

  showPriceRange() {
    if (this.hasMainPriceTarget && this.displayPriceValue) {
      this.mainPriceTarget.textContent = this.displayPriceValue
      this.mainPriceTarget.classList.remove("text-success")
      this.mainPriceTarget.classList.add("text-primary")
    }
    if (this.hasOriginalPriceTarget) {
      this.originalPriceTarget.classList.add("d-none")
    }
    if (this.hasDiscountBadgeTarget) {
      this.discountBadgeTarget.classList.add("d-none")
    }
    if (this.hasPriceTarget) {
      this.priceTarget.textContent = ""
    }
  }

  getSelectedValues() {
    const values = []
    this.selectTargets.forEach(select => {
      if (select.value) {
        values.push(parseInt(select.value))
      }
    })
    return values.sort((a, b) => a - b)
  }

  findMatchingVariant(selectedValues) {
    if (selectedValues.length === 0) return null

    return this.variantsValue.find(variant => {
      const variantValues = variant.attribute_value_ids.sort((a, b) => a - b)
      return JSON.stringify(variantValues) === JSON.stringify(selectedValues)
    })
  }

  updateDisplay(variant) {
    if (this.hasVariantIdTarget) {
      this.variantIdTarget.value = variant.id
    }

    if (this.hasSkuTarget) {
      const effectiveSku = variant.sku || this.defaultSkuValue
      if (effectiveSku) {
        this.skuTarget.textContent = effectiveSku
        this.skuTarget.closest(".sku-container")?.classList.remove("d-none")
      } else {
        this.skuTarget.textContent = "-"
        this.skuTarget.closest(".sku-container")?.classList.add("d-none")
      }
    }

    if (this.hasStockTarget) {
      if (variant.track_stock) {
        if (variant.in_stock) {
          this.stockTarget.innerHTML = `<i class="fa-solid fa-circle-check me-1 text-success"></i> ${this.inStockTextValue}`
        } else {
          this.stockTarget.innerHTML = `<i class="fa-solid fa-circle-xmark me-1 text-danger"></i> ${this.outOfStockTextValue}`
        }
      } else {
        this.stockTarget.innerHTML = `<i class="fa-solid fa-circle-check me-1 text-success"></i> ${this.inStockTextValue}`
      }
    }

    if (this.hasImageTarget) {
      const imageUrl = variant.photo_url || this.originalImageUrl
      this.imageTarget.src = imageUrl
      if (this.hasZoomImageTarget) {
        this.zoomImageTarget.src = imageUrl
      }
    }
  }

  enableAddToCart(variant) {
    if (this.hasAddToCartTarget) {
      if (variant.purchasable) {
        this.addToCartTarget.disabled = false
        this.addToCartTarget.classList.remove("btn-secondary")
        this.addToCartTarget.classList.add("btn-primary")
      } else {
        this.disableAddToCart()
      }
    }
  }

  disableAddToCart() {
    if (this.hasAddToCartTarget) {
      this.addToCartTarget.disabled = true
      this.addToCartTarget.classList.remove("btn-primary")
      this.addToCartTarget.classList.add("btn-secondary")
    }
  }

  formatPrice(cents) {
    const amount = (cents / 100).toFixed(2)
    return `${this.currencySymbolValue}${amount}`
  }
}
