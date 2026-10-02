const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const puppeteer = require('puppeteer')

const chrome = process.env.PUPPETEER_EXECUTABLE_PATH || (fs.existsSync(puppeteer.executablePath()) ? puppeteer.executablePath() : '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')

test('variant edits survive pagination, filtering and form submission', { skip: !fs.existsSync(chrome) }, async () => {
  const browser = await puppeteer.launch({ headless: true, executablePath: chrome })
  try {
    const page = await browser.newPage()
    await page.setContent(`<form>
      <input type="radio" name="target_type" value="category" checked>
      <select name="scope_config[mode]"><option>include</option><option>exclude</option></select>
      <select name="scope_config[category_ids][]" multiple><option value="9" selected>A</option></select>
      <turbo-frame id="variant-overrides"><input type="checkbox" name="variant_overrides[11][exclude_from_discounts]" value="1"><select name="variant_overrides[11][custom_discount_type]"><option value=""></option><option>percentage</option></select><input name="variant_overrides[11][custom_discount_value]" value=""></turbo-frame>
      <div id="changes"></div>
    </form>`)
    await page.addScriptTag({ content: fs.readFileSync('app/javascript/controllers/variant_overrides_controller.js', 'utf8').replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}').replace('export default class', 'window.VariantOverrides = class') })
    const result = await page.evaluate(() => {
      customElements.define('turbo-frame', class extends HTMLElement {
        set src(value) { this.setAttribute('src', value) }
        get src() { return this.getAttribute('src') }
      })
      const controller = new VariantOverrides()
      controller.element = document.querySelector('form')
      controller.changesTarget = document.getElementById('changes')
      controller.urlValue = '/variants'
      controller.application = { getControllerForElementAndIdentifier: () => null }
      controller.connect()
      const frame = document.getElementById('variant-overrides')
      const original = frame.innerHTML
      const checkbox = frame.querySelector('input[type=checkbox]')
      checkbox.checked = true
      checkbox.dispatchEvent(new Event('change', { bubbles: true }))
      frame.querySelector('select').value = 'percentage'
      const value = frame.querySelector('input:not([type=checkbox])')
      value.value = '0.15'
      value.dispatchEvent(new Event('input', { bubbles: true }))
      controller.reload(2)
      const pageURL = frame.getAttribute('src')
      frame.innerHTML = '<p>Another page</p>'
      const staged = new FormData(controller.element).get('variant_overrides[11][custom_discount_value]')
      frame.innerHTML = original
      frame.dispatchEvent(new Event('turbo:frame-load', { bubbles: true }))
      const restored = [frame.querySelector('input[type=checkbox]').checked, frame.querySelector('select').value, frame.querySelector('input:not([type=checkbox])').value]
      document.querySelector('[name="scope_config[mode]"]').value = 'exclude'
      controller.element.dispatchEvent(new CustomEvent('variant-overrides:reload', { bubbles: true }))
      const scopeURL = frame.getAttribute('src')
      frame.querySelector('input[type=checkbox]').checked = false
      frame.querySelector('input[type=checkbox]').dispatchEvent(new Event('change', { bubbles: true }))
      frame.innerHTML = ''
      const excluded = new FormData(controller.element).get('variant_overrides[11][exclude_from_discounts]')
      controller.disconnect()
      return { pageURL, staged, restored, scopeURL, excluded }
    })
    assert.match(result.pageURL, /variant_page=2/)
    assert.equal(result.staged, '0.15')
    assert.deepEqual(result.restored, [true, 'percentage', '0.15'])
    assert.match(result.scopeURL, /scope_mode=exclude/)
    assert.match(result.scopeURL, /variant_page=1/)
    assert.equal(result.excluded, '0')
  } finally { await browser.close() }
})
