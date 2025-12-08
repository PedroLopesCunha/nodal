import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="checkout"
export default class extends Controller {
    static targets = ["shippingAmount", "totalAmount"]
    static values = {
        subtotal: Number,
        tax: Number,
        shippingCost: Number
    }

    updateTotal() {
        const isPickup = document.getElementById("delivery_method_pickup").checked
        const shipping = isPickup ? 0 : this.shippingCostValue
        const total = this.subtotalValue + this.taxValue + shipping

        this.shippingAmountTarget.textContent = this.formatCurrency(shipping)
        this.totalAmountTarget.textContent = this.formatCurrency(total)
    }

    formatCurrency(cents) {
        const amount = (cents / 100).toFixed(2)
        return `€${amount}`
    }
}
