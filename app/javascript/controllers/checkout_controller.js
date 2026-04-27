import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="checkout"
export default class extends Controller {
    static targets = [
        "shippingAmount", "totalAmount", "shippingAddressSection",
        "shippingSelector", "sameAsBillingOption", "dateLabel",
        "newShippingAddressForm", "deliveryShippingCost", "dateField"
    ]
    static values = {
        subtotal: Number,
        tax: Number,
        shippingCost: Number,
        currencySymbol: String,
        freeShippingThreshold: Number,
        freeShippingEnabled: Boolean,
        deliveryLabel: String,
        pickupLabel: String,
        deliveryDays: Array,
        earliestDate: String
    }

    connect() {
        this.toggleShippingAddress()
    }

    qualifiesForFreeShipping() {
        return this.freeShippingEnabledValue &&
               this.freeShippingThresholdValue > 0 &&
               this.subtotalValue >= this.freeShippingThresholdValue
    }

    updateTotal() {
        const isPickup = document.getElementById("delivery_method_pickup").checked
        const qualifiesForFree = this.qualifiesForFreeShipping()
        const shipping = isPickup || qualifiesForFree ? 0 : this.shippingCostValue
        const total = this.subtotalValue + this.taxValue + shipping

        if (this.hasShippingAmountTarget) this.shippingAmountTarget.textContent = this.formatCurrency(shipping)
        if (this.hasTotalAmountTarget) this.totalAmountTarget.textContent = this.formatCurrency(total)
    }

    toggleShippingAddress() {
        const isPickup = document.getElementById("delivery_method_pickup").checked
        const sameAsBillingEl = document.getElementById("same_as_billing")
        const sameAsBilling = sameAsBillingEl ? sameAsBillingEl.checked : false

        // Whole shipping card hides only when pickup is selected.
        if (this.hasShippingAddressSectionTarget) {
            this.shippingAddressSectionTarget.style.display = isPickup ? "none" : "block"
        }

        // Inner shipping selector hides when shipping to billing address —
        // the checkbox stays visible so the customer can flip it back.
        if (this.hasShippingSelectorTarget) {
            this.shippingSelectorTarget.style.display = sameAsBilling ? "none" : "block"
        }

        if (this.hasDateLabelTarget) {
            this.dateLabelTarget.textContent = isPickup ? this.pickupLabelValue : this.deliveryLabelValue
        }
    }

    toggleNewShippingAddress(event) {
        if (this.hasNewShippingAddressFormTarget) {
            const isNew = event.target.value === "new"
            this.newShippingAddressFormTarget.style.display = isNew ? "block" : "none"
        }
    }

    validateDate() {
        if (!this.hasDateFieldTarget || !this.hasDeliveryDaysValue) return

        const selected = this.dateFieldTarget.value
        if (!selected) return

        const date = new Date(selected + "T00:00:00")
        const dayOfWeek = date.getDay()

        if (!this.deliveryDaysValue.includes(dayOfWeek)) {
            this.dateFieldTarget.value = this.earliestDateValue
        }
    }

    formatCurrency(cents) {
        const amount = (cents / 100).toFixed(2)
        const symbol = this.currencySymbolValue || '€'
        return `${symbol}${amount}`
    }
}
