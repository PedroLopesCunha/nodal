const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')

const source = fs.readFileSync('app/javascript/controllers/checkout_controller.js', 'utf8')
  .replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')
  .replace('export default class', 'globalThis.Checkout = class')

test('switching delivery and pickup preserves the customer net total and free shipping basis', () => {
  const pickup = { checked: false }
  const context = { document: { getElementById: () => pickup } }
  vm.createContext(context)
  vm.runInContext(source, context)
  const c = new context.Checkout()
  Object.assign(c, {
    subtotalValue: 6800, taxValue: 1564, shippingCostValue: 500,
    freeShippingEnabledValue: true, freeShippingThresholdValue: 7000,
    hasFreeShippingSubtotalValue: true, freeShippingSubtotalValue: 7200,
    hasTotalAmountTarget: true, totalAmountTarget: {}, currencySymbolValue: '€'
  })
  // Coupon reduces the payable subtotal; the existing free-shipping rule uses
  // the campaign subtotal with the ERP discount, before the coupon.
  c.updateTotal()
  assert.equal(c.totalAmountTarget.textContent, '€83.64')
  c.freeShippingThresholdValue = 8000
  c.updateTotal()
  assert.equal(c.totalAmountTarget.textContent, '€88.64')
  pickup.checked = true
  c.updateTotal()
  assert.equal(c.totalAmountTarget.textContent, '€83.64')
})
