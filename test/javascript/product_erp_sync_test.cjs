const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const puppeteer = require('puppeteer')
const chrome = process.env.PUPPETEER_EXECUTABLE_PATH || (fs.existsSync(puppeteer.executablePath()) ? puppeteer.executablePath() : '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')

test('product ERP sync stays inline, refreshes success and displays errors', { skip: !fs.existsSync(chrome) }, async (t) => {
  const browser = await puppeteer.launch({ headless: true, executablePath: chrome })
  try {
    for (const outcome of ['completed', 'failed', 'running']) {
      await t.test(outcome, async () => {
        const page = await browser.newPage()
        try {
          await page.setContent('<meta name="csrf-token" content="test"><div id="product-details"><form action="https://local.test/sync"><button>Sync</button></form><div data-product-erp-sync-target="message"></div><span>Old price</span></div>')
          await page.addScriptTag({ content: fs.readFileSync('app/javascript/controllers/product_erp_sync_controller.js', 'utf8').replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}').replace('export default class', 'window.ProductErpSync = class') })
          const result = await page.evaluate(async (outcome) => {
            const requests = []
            window.setTimeout = () => 1
            window.fetch = async (url, options) => {
              requests.push({ url, method: options?.method })
              if (url.endsWith('/sync')) return { ok: true, json: async () => ({ status_url: '/status' }) }
              if (url === '/status') return { ok: true, json: async () => ({ status: outcome, error_message: 'ERP unavailable' }) }
              return { ok: true, text: async () => '<div id="product-details"><div data-product-erp-sync-target="message"></div><span>New price</span><button>Sync</button></div>' }
            }
            const c = new ProductErpSync()
            c.element = document.getElementById('product-details')
            c.buttonTarget = c.element.querySelector('button')
            c.messageTarget = c.element.querySelector('[data-product-erp-sync-target=message]')
            c.refreshUrlValue = '/product'
            c.pendingTextValue = 'Syncing'
            c.successTextValue = 'Success'
            c.errorTextValue = 'Failure'
            c.refreshErrorTextValue = 'Reload'
            c.connect()
            const event = { preventDefault() {}, currentTarget: c.element.querySelector('form') }
            await c.start(event)
            if (outcome === 'running') await c.start(event)
            const root = document.getElementById('product-details')
            return { requests, message: root.querySelector('[data-product-erp-sync-target=message]').textContent, contents: root.textContent, disabled: c.buttonTarget.disabled, location: location.href }
          }, outcome)
          assert.equal(result.location, 'about:blank')
          assert.equal(result.requests.filter(r => r.method === 'POST').length, 1)
          if (outcome === 'completed') {
            assert.equal(result.message, 'Success')
            assert.match(result.contents, /New price/)
          } else if (outcome === 'failed') {
            assert.equal(result.message, 'ERP unavailable')
            assert.equal(result.disabled, false)
            assert.equal(result.requests.length, 2)
          } else {
            assert.equal(result.message, 'Syncing')
            assert.equal(result.disabled, true)
            assert.equal(result.requests.length, 2)
          }
        } finally { await page.close() }
      })
    }
  } finally { await browser.close() }
})
