import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["changes"]
  static values = { url: String }

  connect() {
    this.reloadHandler = () => this.reload()
    this.loadHandler = () => this.restore()
    this.changeHandler = (event) => this.remember(event.target)
    this.element.addEventListener("variant-overrides:reload", this.reloadHandler)
    this.element.addEventListener("turbo:frame-load", this.loadHandler)
    this.element.addEventListener("input", this.changeHandler)
    this.element.addEventListener("change", this.changeHandler)
    this.restore()
  }

  disconnect() {
    clearTimeout(this.searchTimer)
    this.element.removeEventListener("variant-overrides:reload", this.reloadHandler)
    this.element.removeEventListener("turbo:frame-load", this.loadHandler)
    this.element.removeEventListener("input", this.changeHandler)
    this.element.removeEventListener("change", this.changeHandler)
  }

  change() { this.reload() }

  remember(field) {
    if (!field.name?.startsWith("variant_overrides[") || field.type === "hidden") return
    const match = field.name.match(/^variant_overrides\[(\d+)\]/)
    if (!match) return
    // Preserve the entire row: an unchecked exclusion is a deliberate zero.
    this.element.querySelectorAll(`#variant-overrides [name^='variant_overrides[${match[1]}]']`).forEach(input => {
      if (input.type === "hidden") return
      let saved = Array.from(this.changesTarget.children).find(child => child.name === input.name)
      if (!saved) {
        saved = document.createElement("input")
        saved.type = "hidden"
        saved.name = input.name
        this.changesTarget.append(saved)
      }
      saved.value = input.type === "checkbox" ? (input.checked ? "1" : "0") : input.value
    })
  }

  restore() {
    const fields = this.element.querySelectorAll("#variant-overrides input, #variant-overrides select")
    this.changesTarget.querySelectorAll("input").forEach(saved => {
      const field = Array.from(fields).find(input => input.name === saved.name && input.type !== "hidden")
      if (!field) return
      if (field.type === "checkbox") field.checked = saved.value === "1"
      else field.value = saved.value
    })
    // Update previews after restoring values without marking untouched rows dirty.
    this.element.querySelectorAll("#variant-overrides [data-controller='discount-preview']").forEach(element => {
      this.application.getControllerForElementAndIdentifier(element, "discount-preview")?.recalculate()
    })
    if (this.focusSearch) {
      const search = this.element.querySelector("#variant-overrides input[type=search]")
      search?.focus()
      search?.setSelectionRange(search.value.length, search.value.length)
      this.focusSearch = false
    }
  }

  search(event) {
    this.query = event.target.value
    this.focusSearch = true
    clearTimeout(this.searchTimer)
    this.searchTimer = setTimeout(() => this.reload(1), 400)
  }

  searchNow(event) {
    event.preventDefault()
    this.query = event.target.value
    clearTimeout(this.searchTimer)
    this.reload(1)
  }

  page(event) { this.reload(Number(event.currentTarget.dataset.page)) }

  reload(page = 1) {
    clearTimeout(this.searchTimer)
    const frame = this.element.querySelector("#variant-overrides")
    if (!frame) return
    const query = new URLSearchParams({ variant_page: page, variant_query: this.query || "" })
    const target = this.element.querySelector("input[name=target_type]:checked")?.value
    if (target === "product") {
      const product = this.element.querySelector("[data-discount-target-target=productSelect]")?.value
      if (!product) { frame.removeAttribute("src"); frame.innerHTML = ""; return }
      query.set("product_id", product)
    } else {
      const mode = this.element.querySelector("[name='scope_config[mode]']")
      const categories = this.element.querySelector("select[name='scope_config[category_ids][]']")
      if (mode && categories) {
        query.set("scope_mode", mode.value)
        if (mode.value !== "all") Array.from(categories.selectedOptions).forEach(option => query.append("category_ids[]", option.value))
      } else {
        query.set("category_id", this.element.querySelector("[data-discount-target-target=categorySelect]")?.value || "")
      }
    }
    const src = `${this.urlValue}?${query}`
    if (frame.getAttribute("src") === src) frame.removeAttribute("src")
    frame.src = src
  }
}
