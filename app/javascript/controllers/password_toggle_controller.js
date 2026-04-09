import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "showIcon", "hideIcon", "label"]

  connect() {
    this.render()
  }

  toggle() {
    const shouldShow = this.inputTarget.type === "password"
    this.inputTarget.type = shouldShow ? "text" : "password"
    this.render()
  }

  render() {
    const isVisible = this.inputTarget.type === "text"

    if (this.hasShowIconTarget) {
      this.showIconTarget.hidden = isVisible
    }

    if (this.hasHideIconTarget) {
      this.hideIconTarget.hidden = !isVisible
    }

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = isVisible ? "Hide password" : "Show password"
    }
  }
}
