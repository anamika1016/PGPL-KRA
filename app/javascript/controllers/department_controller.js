import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["select"];

  connect() {
    this.selectTarget.addEventListener("change", () => this.loadTable());
  }

  loadTable() {
    const departmentId = this.selectTarget.value;
    if (!departmentId) return;

    fetch(`/user_details/load_activities?department_id=${departmentId}`, {
      headers: { Accept: "text/vnd.turbo-stream.html" },
    })
      .then((res) => res.text())
      .then((html) => {
        document.getElementById("activity-table").innerHTML = html;
      });
  }
}
