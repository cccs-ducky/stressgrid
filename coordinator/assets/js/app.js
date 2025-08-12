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
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

import React from 'react'
import ReactDOM from 'react-dom/client'
import { Sparklines, SparklinesLine, SparklinesSpots } from "react-sparklines"

import { EditorView, basicSetup } from "codemirror"
import { EditorState } from "@codemirror/state"
import { json } from "@codemirror/lang-json"
import { elixir } from "codemirror-lang-elixir"
import { oneDark } from "@codemirror/theme-one-dark"

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
      if (e.key === "Escape" && !e.shiftKey) {
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
      if (e.key === "Enter" && !e.shiftKey) {
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

Hooks.Sparkline = {
  renderSparkline() {

    const renderSparkline = () => {
      const sparklinesElement = React.createElement(
        Sparklines,
        { data: this.el.dataset.points.split(',').map(Number), height: 20 },
        [
          React.createElement(SparklinesLine, { key: 'line', style: { fill: "none" } }, null),
          React.createElement(SparklinesSpots, { key: 'spots' }, null)
        ]
      );

      if (!this.root) {
        this.root = ReactDOM.createRoot(this.el);
      }

      this.root.render(sparklinesElement);
    };

    renderSparkline();

    const observer = new MutationObserver(function(mutations) {
      renderSparkline();
    });

    observer.observe(this.el, {
      attributes: true,
      attributeFilter: ['data-points']
    });
  },

  mounted() {
    this.renderSparkline();
  }
}

Hooks.CodeEditor = {
  mounted() {
    this.initializeEditor()

    // Listen for theme changes
    this.themeObserver = new MutationObserver(() => {
      const isDarkNow = document.documentElement.classList.contains('dark')
      if (isDarkNow !== this.isDark) {
        this.recreateEditor()
      }
    })

    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['class']
    })

    // Listen for external updates from LiveView
    this.handleEvent("update_editor", ({ field, value }) => {
      if (field === this.field && this.view) {
        const currentDoc = this.view.state.doc.toString()
        if (currentDoc !== value) {
          this.view.dispatch({
            changes: { from: 0, to: currentDoc.length, insert: value }
          })
        }
      }
    })
  },

  initializeEditor() {
    const container = this.el
    const textarea = container.querySelector('textarea')
    const lang = container.dataset.lang

    this.field = container.dataset.field
    this.isDark = document.documentElement.classList.contains('dark')

    // Determine language extension
    let languageExtension
    if (lang === 'json') {
      languageExtension = json()
    } else if (lang === 'elixir') {
      languageExtension = elixir()
    }

    // Create extensions array
    const extensions = [basicSetup]
    if (languageExtension) {
      extensions.push(languageExtension)
    }
    if (this.isDark) {
      extensions.push(oneDark)
    }

    // Create editor state
    const startState = EditorState.create({
      doc: textarea.value,
      extensions: extensions
    })

    // Create editor view
    this.view = new EditorView({
      state: startState,
      parent: container,
      dispatch: (tr) => {
        this.view.update([tr])
        if (tr.docChanged) {
          const newValue = this.view.state.doc.toString()
          textarea.value = newValue
          // Trigger the phx-change event manually
          textarea.dispatchEvent(new Event('input', { bubbles: true }))
        }
      }
    })

    // Hide original textarea
    textarea.style.display = 'none'

    // Style the editor
    this.styleEditor()
  },

  styleEditor() {
    if (!this.view) return

    this.view.dom.style.border = '1px solid'
    this.view.dom.style.borderRadius = '0.375rem'
    this.view.dom.style.fontSize = '0.875rem'
    this.view.dom.style.fontFamily = 'ui-monospace, SFMono-Regular, "SF Mono", Consolas, "Liberation Mono", Menlo, monospace'

    // Use smaller min-height for params field
    if (this.field === 'params') {
      this.view.dom.style.minHeight = '2rem'
    } else {
      this.view.dom.style.minHeight = '8rem'
    }

    if (this.isDark) {
      this.view.dom.style.borderColor = 'rgb(55 65 81)'
    } else {
      this.view.dom.style.borderColor = 'rgb(209 213 219)'
    }
  },

  recreateEditor() {
    if (this.view) {
      const currentDoc = this.view.state.doc.toString()
      const container = this.el
      const textarea = container.querySelector('textarea')
      const lang = container.dataset.lang
      this.isDark = document.documentElement.classList.contains('dark')

      // Destroy current view
      this.view.destroy()

      // Determine language extension
      let languageExtension

      if (lang === 'json') {
        languageExtension = json()
      } else if (lang === 'elixir') {
        languageExtension = elixir()
      }

      // Create extensions array
      const extensions = [basicSetup]
      if (languageExtension) {
        extensions.push(languageExtension)
      }
      if (this.isDark) {
        extensions.push(oneDark)
      }

      // Create new editor state
      const startState = EditorState.create({
        doc: currentDoc,
        extensions: extensions
      })

      // Create new editor view
      this.view = new EditorView({
        state: startState,
        parent: container,
        dispatch: (tr) => {
          this.view.update([tr])
          if (tr.docChanged) {
            const newValue = this.view.state.doc.toString()
            textarea.value = newValue
            textarea.dispatchEvent(new Event('input', { bubbles: true }))
          }
        }
      })

      // Style the new editor
      this.styleEditor()
    }d
  },

  destroyed() {
    if (this.view) {
      this.view.destroy()
    }
    if (this.themeObserver) {
      this.themeObserver.disconnect()
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })

window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
