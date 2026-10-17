import Quickshell
import QtQuick
import qs.Ui
import qs.Commons

// Loads the real BarWidget.qml (and through it Panel.qml, Service.qml and
// AboutView.qml) the way the bar hosts a third-party widget, then drives the
// About page: the info button, the `i` and Esc keys, the license and notices,
// Back, the `about` IPC call and closing. Never presses Email or Copy (they
// would open a mail app or replace the clipboard). Prints one RESULT line of
// JSON for tests/panel.test.sh. Run only through that script.
ShellRoot {
  id: h

  readonly property string pluginDir: Quickshell.env("HEY_CALENDAR_PLUGIN")
  property var persisted: []
  property var results: []

  property var w: widgetLoader.item
  property var panel: null
  property var keys: null

  function check(name, cond, detail) {
    var next = h.results.slice()
    next.push({ name: name, ok: !!cond, detail: String(detail === undefined ? "" : detail) })
    h.results = next
  }

  function finish() {
    console.log("RESULT " + JSON.stringify(h.results))
    Qt.quit()
  }

  // Depth-first search of the object tree, through popup windows and loaders.
  function find(obj, pred, seen) {
    if (!obj) return null
    seen = seen || []
    if (seen.indexOf(obj) >= 0) return null
    seen.push(obj)
    if (pred(obj)) return obj
    var kids = []
    try { if (obj.children) for (var i = 0; i < obj.children.length; i++) kids.push(obj.children[i]) } catch (e) {}
    try { if (obj.data) for (var j = 0; j < obj.data.length; j++) kids.push(obj.data[j]) } catch (e) {}
    try { if (obj.contentItem) kids.push(obj.contentItem) } catch (e) {}
    try { if (obj.item) kids.push(obj.item) } catch (e) {}
    for (var k = 0; k < kids.length; k++) {
      var found = find(kids[k], pred, seen)
      if (found) return found
    }
    return null
  }

  function byName(name) { return h.find(h.panel, function(o) { return o.objectName === name }) }

  PluginBarApi {
    id: hostBar
    pluginId: "ninepointlabs.hey-calendar"
    moduleName: "ninepointlabs.hey-calendar"
    shell: hostShell
    foreground: "#cacccc"
    barForeground: "#cacccc"
    background: "#101315"
    urgent: "#a55555"
    barSize: 26
    _moduleWidgets: function(id) { return widgetLoader.item ? [widgetLoader.item] : [] }
    _switchPanelFrom: function(owner, direction) { return false }
    _targetBelongsToWindow: function(target, window) { return false }
  }

  QtObject {
    id: hostShell
    function serviceFor(id) { return null }
    function updateEntryInline(id, entry) {
      var log = h.persisted.slice()
      log.push(JSON.parse(JSON.stringify(entry)))
      h.persisted = log
      return true
    }
  }

  Loader {
    id: widgetLoader
    source: "file://" + h.pluginDir + "/BarWidget.qml"
    onLoaded: {
      item.bar = hostBar
      item.settings = { view: "month", showNextEvent: true }
    }
    onStatusChanged: if (status === Loader.Error) { h.check("BarWidget.qml loads", false); h.finish() }
  }

  // One step per tick so bindings, the panel loader and the service settle in
  // between.
  readonly property var steps: [
    function() {
      h.panel = h.find(h.w, function(o) { return typeof o.openAbout === "function" })
      h.keys = h.find(h.panel, function(o) { return o.blocked !== undefined && o.tabRequested !== undefined })
      h.check("panel loaded", !!h.panel)
      h.check("key catcher found", !!h.keys)
      h.w.open()
    },
    function() {
      var aboutButton = h.byName("aboutButton")
      h.check("About button in the header", !!aboutButton && aboutButton.visible)
      h.check("About hidden at first", h.panel.showAbout === false && !h.byName("aboutVersion").visible)
      aboutButton.clicked()
      h.check("About button opens the About page", h.panel.showAbout === true && h.byName("aboutVersion").visible
        && !h.byName("aboutButton").visible)
    },
    function() {
      h.check("About shows the manifest version", /^Version @MANIFEST_VERSION_RE@$/.test(h.byName("aboutVersion").text), h.byName("aboutVersion").text)
      h.check("About states privacy", String(h.byName("aboutPrivacy").text).indexOf("No telemetry") === 0)
      h.check("About credits Nine Point Labs", !!h.find(h.panel, function(o) { return o.text === "Nine Point Labs" }))
      h.check("license summary from LICENSE", h.byName("aboutLicenseSummary").text === "MIT License, © 2026 Nine Point Labs",
        h.byName("aboutLicenseSummary").text)
      h.check("Built with names the toolkit and HEY CLI",
        /^Built with Quickshell 0\.\d+, Qt 6\.\d+, HEY CLI 9\.8\.7$/.test(h.byName("aboutBuiltWith").text), h.byName("aboutBuiltWith").text)
      h.check("license text hidden at first", !h.byName("aboutLicenseText").visible)
      h.byName("aboutLicense").clicked()
      h.byName("aboutNotices").clicked()
    },
    function() {
      var text = h.byName("aboutLicenseText")
      h.check("license text readable", text.visible && String(text.text).indexOf("MIT License\n\nCopyright (c) 2026 Nine Point Labs") === 0,
        String(text.text).substring(0, 60))
      var notices = h.byName("aboutNoticesText")
      h.check("third-party notices readable", notices.visible && String(notices.text).indexOf("37signals") >= 0,
        String(notices.text).substring(0, 60))
      var view = h.find(h.panel, function(o) { return o.details !== undefined && o.backRequested !== undefined })
      h.check("version details", /^HEY Calendar @MANIFEST_VERSION_RE@\nQuickshell 0\.\d+, Qt 6\.\d+, HEY CLI 9\.8\.7\n/.test(view.details), view.details)
      h.check("Copy version details button", !!h.byName("aboutCopyDetails"))
      h.keys.closeRequested()
      h.check("Esc returns to the calendar, panel stays open", h.panel.showAbout === false && h.w.opened === true
        && h.byName("aboutButton").visible)
      h.keys.textKey("i")
      h.check("i opens About", h.panel.showAbout === true)
    },
    function() {
      h.check("reopened About starts with the license folded", !h.byName("aboutLicenseText").visible && !h.byName("aboutNoticesText").visible)
      h.byName("aboutBack").clicked()
      h.check("Back returns to the calendar", h.panel.showAbout === false && h.byName("aboutButton").visible)
      h.w.close()
    },
    function() {
      var ipc = h.find(h.w, function(o) { return typeof o.about === "function" && typeof o.journalEditFinished === "function" })
      h.check("IPC about() exists", !!ipc)
      ipc.about()
      h.check("IPC about opens the panel on About", h.w.opened === true && h.panel.showAbout === true)
      h.w.close()
      h.check("closing the panel leaves About", h.panel.showAbout === false && h.w.opened === false)
      h.check("About wrote no settings", h.persisted.length === 0, JSON.stringify(h.persisted))
      h.finish()
    }
  ]

  property int step: 0
  Timer {
    interval: 400
    repeat: true
    running: h.w !== null
    onTriggered: {
      if (h.step >= h.steps.length) return
      try {
        h.steps[h.step++]()
      } catch (e) {
        h.check("step " + h.step + " ran", false, e)
        h.finish()
      }
    }
  }
}
