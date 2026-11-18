const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const puppeteer = require('puppeteer')
const chrome = process.env.PUPPETEER_EXECUTABLE_PATH || (fs.existsSync(puppeteer.executablePath()) ? puppeteer.executablePath() : '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')

test('bundle editor adds unique rows and removes them without blocking form validation', { skip: !fs.existsSync(chrome) }, async () => {
  const browser = await puppeteer.launch({ headless: true, executablePath: chrome })
  try {
    const page = await browser.newPage()
    await page.setRequestInterception(true)
    page.on('request', request => request.respond({ status: 200, contentType: 'text/html', body: `<form><div id="rows"><div data-bundle-editor-target="row"><input type="search"><select><option value="1" selected>Existing component</option></select><input name="product[bundle_components_attributes][0][_destroy]" value="0"><button type="button">Remove</button></div></div><template><div data-bundle-editor-target="row"><input name="product[bundle_components_attributes][NEW_COMPONENT][_destroy]" value="0"><button type="button">Remove</button></div></template></form>` }))
    await page.goto('https://bundle.test')
    await page.addScriptTag({ content: fs.readFileSync('app/javascript/controllers/bundle_editor_controller.js', 'utf8').replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}').replace('export default class', 'window.BundleEditor = class') })
    const result = await page.evaluate(async () => {
      const c = new BundleEditor()
      c.rowsTarget = document.getElementById('rows')
      c.templateTarget = document.querySelector('template')
      const row = c.rowsTarget.firstElementChild
      c.add()
      c.add()
      const names = [...c.rowsTarget.querySelectorAll('input[name]')].map(i => i.name)
      c.remove({ target: row.querySelector('button') })
      return { names, hidden: row.hidden, disabled: row.querySelector("select").disabled, destroyed: row.querySelector('input[name]').value }
    })
    assert.equal(result.disabled, true)
    assert.equal(new Set(result.names).size, 3)
    result.names.forEach(name => assert.match(name, /bundle_components_attributes\]\[\d+\]/))
    assert.equal(result.hidden, true)
    assert.equal(result.destroyed, '1')
    await page.setContent('<main><section id="product-bundles"><div data-bundle-variant-ids="[1]"></div><div data-bundle-variant-ids="[2]"></div></section></main>')
    await page.addScriptTag({ content: '(function(){' + fs.readFileSync('app/javascript/controllers/variant_selector_controller.js', 'utf8').replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}').replace('export default class', 'window.BundleVariantSelector = class') + '})()' })
    const visibility = await page.evaluate(() => {
      const selector = new BundleVariantSelector()
      selector.element = document.querySelector('main')
      selector.updateBundleOpportunities({ id: 2 })
      const selected = [...document.querySelectorAll('[data-bundle-variant-ids]')].map(row => row.hidden)
      selector.updateBundleOpportunities({ id: 3 })
      const none = document.getElementById('product-bundles').classList.contains('d-none')
      selector.updateBundleOpportunities(null)
      return { selected, none, all: [...document.querySelectorAll('[data-bundle-variant-ids]')].every(row => !row.hidden) }
    })
    assert.deepEqual(visibility, { selected: [true, false], none: true, all: true })
  } finally { await browser.close() }
})
