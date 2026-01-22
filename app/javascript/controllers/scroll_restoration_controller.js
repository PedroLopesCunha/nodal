import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.restoreScrollPosition()
    this.boundSaveScroll = this.saveScrollPosition.bind(this)
    document.addEventListener("turbo:before-visit", this.boundSaveScroll)
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.boundSaveScroll)
  }

  restoreScrollPosition() {
    const key = this.getStorageKey()
    const savedPosition = sessionStorage.getItem(key)

    if (savedPosition) {
      requestAnimationFrame(() => {
        window.scrollTo(0, parseInt(savedPosition))
        sessionStorage.removeItem(key)
      })
    }
  }

  saveScrollPosition(event) {
    // Only save when navigating to a product detail page
    const url = new URL(event.detail.url)
    if (url.pathname.match(/\/products\/[^\/]+$/)) {
      sessionStorage.setItem(this.getStorageKey(), window.scrollY)
    }
  }

  getStorageKey() {
    return `scroll:${window.location.pathname}${window.location.search}`
  }
}
