// Facts and text for the About page (AboutView.qml), kept out of QML so node
// can check them (see tests/about.test.cjs).
//
// The version comes from manifest.json and the license from LICENSE at run
// time, so neither is copied here and neither can drift from the real file.

var NAME = "HEY Calendar"
var TAGLINE = "Today, Week, Month and Year views of your HEY calendar and journal, in the Omarchy bar."
var ORGANIZATION = "Nine Point Labs"
var CREATED = "August 2026" // first commit: 2026-08-31
var SUPPORT_EMAIL = "help@ninepointlabs.com"

// Must stay true to what the plugin does. It runs only the `hey` CLI (see the
// command builders in Model.js), `readlink /etc/localtime`, and, from the
// setup button, `hey auth login` / `omarchy-pkg-aur-add hey-cli` in a
// terminal. Data is held in memory (Service.qml); settings go to shell.json.
var PRIVACY = "No telemetry, and the plugin makes no network requests of its own. Your calendar and "
  + "journal are read and changed only through the HEY CLI (hey), signed in to your own HEY account, "
  + "which talks to HEY (hey.com): hey --version and auth status, calendar list, event list/add/edit/delete and "
  + "journal list/read/write. Events and journal entries are held in memory only; the plugin writes "
  + "none of them to disk. It reads /etc/localtime for your time zone and keeps its settings (default "
  + "view, bar label format) in ~/.config/omarchy/shell.json. The setup button runs hey auth login "
  + "(and installs hey-cli from the AUR if it is missing) in a terminal, only when you click it."

// "0.1.0" from manifest.json's text, or "" when it can't be read.
function manifestVersion(text) {
  var parsed
  try { parsed = JSON.parse(String(text || "")) } catch (e) { return "" }
  var version = parsed && typeof parsed.version === "string" ? parsed.version : ""
  return /^[0-9A-Za-z.+-]{1,32}$/.test(version) ? version : ""
}

// "MIT License, © 2026 Nine Point Labs" from LICENSE's text: its first line
// plus its copyright line, as written there.
function licenseSummary(text) {
  var lines = String(text || "").split("\n")
  var name = ""
  var holder = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    if (name === "") name = line
    var m = /^Copyright\s+(?:\(c\)|©)\s*(.+)$/i.exec(line)
    if (m) { holder = "© " + m[1]; break }
  }
  return holder ? name + ", " + holder : name
}

// LICENSE (or THIRD_PARTY_NOTICES.md) with one line per paragraph, so it
// wraps to the panel's width.
function reflow(text) {
  var paras = String(text || "").replace(/\r/g, "").split(/\n\s*\n/)
  var out = []
  for (var i = 0; i < paras.length; i++) {
    var p = paras[i].split(/\s+/).join(" ").trim()
    if (p !== "") out.push(p)
  }
  return out.join("\n\n")
}

// Highest minor version `has(major, minor)` accepts, as "major.minor"
// (Quickshell.hasVersion / hasQtVersion only answer yes or no), or "".
function probedVersion(has, major) {
  if (typeof has !== "function" || !has(major, 0)) return ""
  var minor = 0
  while (minor < 99 && has(major, minor + 1)) minor++
  return major + "." + minor
}

// { quickshell, qt, hey } -> "Quickshell 0.3, Qt 6.11, HEY CLI 0.2.2"
function builtWith(v) {
  var out = []
  if (v && v.quickshell) out.push("Quickshell " + v.quickshell)
  if (v && v.qt) out.push("Qt " + v.qt)
  if (v && v.hey) out.push("HEY CLI " + v.hey)
  return out.length ? out.join(", ") : "Quickshell and Qt"
}

// Version details to paste into a support email.
function details(version, v, desktop) {
  return NAME + " " + (version || "unknown version") + "\n"
    + builtWith(v) + "\n"
    + (desktop || "unknown desktop")
}

function mailto(version, detailText) {
  return "mailto:" + SUPPORT_EMAIL
    + "?subject=" + encodeURIComponent(NAME + " " + (version || ""))
    + "&body=" + encodeURIComponent("\n\n--\n" + detailText)
}

if (typeof module !== "undefined") {
  module.exports = {
    NAME: NAME, TAGLINE: TAGLINE, ORGANIZATION: ORGANIZATION, CREATED: CREATED,
    SUPPORT_EMAIL: SUPPORT_EMAIL, PRIVACY: PRIVACY,
    manifestVersion: manifestVersion, licenseSummary: licenseSummary, reflow: reflow,
    probedVersion: probedVersion, builtWith: builtWith, details: details, mailto: mailto
  }
}
