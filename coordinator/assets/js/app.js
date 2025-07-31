// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

const Hooks = {}

Hooks.SettingsStorage = {
  mounted() {
    const keys = [
      "name", "host", "port", "protocol", "script", "params",
      "desired_size", "rampup_secs", "sustain_secs", "rampdown_secs", "json", "advanced"
    ];

    const settings = {};

    keys.forEach(k => {
      const v = localStorage.getItem("sg_" + k);

      settings[k] = k === "advanced" ? v === "true" : v;
    });

    this.pushEvent("load_settings", settings);

    this._saveSettingsHandler = (event) => {
      Object.entries(event.detail).forEach(([k, v]) => {
        localStorage.setItem("sg_" + k, v);
      });
    };

    window.addEventListener("phx:save_settings", this._saveSettingsHandler);
  },
  destroyed() {
    window.removeEventListener("phx:save_settings", this._saveSettingsHandler);
  }
}

Hooks.PlanModal = {
  mounted() {
    this._escHandler = (e) => {
      if (e.key === "Escape") {
        this.pushEvent("hide_plan_modal", {});
      }
    };

    this._enterHandler = (e) => {
      if (
        e.key === "Enter" &&
        !e.shiftKey
      ) {
        const form = document.getElementById("plan-modal").querySelector("form");

        if (form) {
          e.preventDefault();

          form.querySelector("[type=submit]").click();
        }
      }
    };

    window.addEventListener("keydown", this._escHandler);
    window.addEventListener("keydown", this._enterHandler);
  },
  destroyed() {
    window.removeEventListener("keydown", this._escHandler);
    window.removeEventListener("keydown", this._enterHandler);
  }
}

Hooks.CurrentRun = {
  mounted() {
    this._enterHandler = (e) => {
      if (e.key === "Enter") {
        const showPlanModalButton = this.el.querySelector('button[phx-click="show_plan_modal"]');
        const abortRunButton = this.el.querySelector('button[phx-click="abort_run"]');

        if (abortRunButton) {
          e.preventDefault();

          abortRunButton.click();
        } else if (showPlanModalButton) {
          e.preventDefault();

          showPlanModalButton.click();
        }
      }
    };

    window.addEventListener("keydown", this._enterHandler);
  },
  destroyed() {
    window.removeEventListener("keydown", this._enterHandler);
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})

window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())


// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
