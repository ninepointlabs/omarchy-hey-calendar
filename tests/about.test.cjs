// Node test runner (`node --test tests/`) for the About page's facts: they
// come from the repo's own files (manifest.json, LICENSE, git history), so
// these check About.js against the real files.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { execFileSync } = require("node:child_process")
const About = require("../About.js")

const ROOT = path.join(__dirname, "..")
const read = (name) => fs.readFileSync(path.join(ROOT, name), "utf8")

test("version comes from manifest.json", () => {
  const manifest = JSON.parse(read("manifest.json"))
  assert.equal(About.manifestVersion(read("manifest.json")), manifest.version)
  assert.match(About.manifestVersion(read("manifest.json")), /^\d+\.\d+\.\d+$/)
  assert.equal(About.manifestVersion("not json"), "")
  assert.equal(About.manifestVersion('{"version":"1.0 <b>"}'), "")
  assert.equal(About.NAME, manifest.name)
  assert.equal(manifest.author, "Nine Point Labs")
})

test("license summary and text come from LICENSE", () => {
  const text = read("LICENSE")
  assert.equal(About.licenseSummary(text), "MIT License, © 2026 Nine Point Labs")
  const body = About.reflow(text)
  assert.ok(body.startsWith("MIT License\n\nCopyright (c) 2026 Nine Point Labs\n\nPermission is hereby granted"))
  assert.ok(body.includes("THE SOFTWARE IS PROVIDED \"AS IS\""))
  assert.ok(!/\n(?!\n)/.test(body.replace(/\n\n/g, "")), "one line per paragraph")
  assert.ok(About.reflow(read("THIRD_PARTY_NOTICES.md")).includes("37signals LLC"))
})

test("no 'Ninepoint' spelling left in the repo", () => {
  const files = execFileSync("git", ["ls-files"], { cwd: ROOT, encoding: "utf8" }).split("\n")
    .filter((f) => f && !/\.png$/.test(f))
  // Built from parts so this file doesn't match itself.
  const oldSpelling = new RegExp("ninepoint" + " labs", "i")
  for (const f of files) assert.ok(!oldSpelling.test(read(f)), f)
})

test("facts: Nine Point Labs, created date, support address", () => {
  assert.equal(About.ORGANIZATION, "Nine Point Labs")
  assert.equal(About.SUPPORT_EMAIL, "help@ninepointlabs.com")
  const first = execFileSync("git", ["log", "--reverse", "--format=%ad", "--date=format:%B %Y"], { cwd: ROOT, encoding: "utf8" }).split("\n")[0]
  assert.equal(About.CREATED, first)
})

test("privacy statement is specific, and names every host the plugin's code mentions", () => {
  assert.match(About.PRIVACY, /No telemetry/)
  assert.match(About.PRIVACY, /no network requests of its own/)
  assert.match(About.PRIVACY, /HEY CLI \(hey\)/)
  assert.match(About.PRIVACY, /~\/\.config\/omarchy\/shell\.json/)
  // Every `hey` subcommand the plugin builds is named.
  const model = read("Model.js")
  const subcommands = new Set()
  for (const m of model.matchAll(/\["hey", "([a-z]+)", "([a-z]+)"/g)) subcommands.add(m[1] + " " + m[2])
  assert.ok(subcommands.size >= 8, [...subcommands].join(", "))
  for (const sub of subcommands) {
    const [group, verb] = sub.split(" ")
    assert.match(About.PRIVACY, new RegExp(group + " [a-z/]*\\b" + verb + "\\b"), sub)
  }
  // Any host in the plugin's code must be named in the privacy text.
  const hosts = new Set()
  for (const f of fs.readdirSync(ROOT)) {
    if (!/\.(qml|js|sh)$/.test(f) || f === "About.js") continue
    const text = read(f)
    for (const m of text.matchAll(/\b[a-z][a-z0-9+.-]*:\/\/([^/"'\s$)]+)/gi)) {
      if (!/^(file|qrc|mailto)$/i.test(m[0].split(":")[0])) hosts.add(m[1])
    }
    for (const m of text.matchAll(/\b(?:curl|wget|XMLHttpRequest|WebSocket|fetch\()/g)) hosts.add("network call: " + m[0])
  }
  for (const host of hosts) assert.ok(About.PRIVACY.includes(host), host + " is used but not named in PRIVACY")
})

test("Built with, version details and mailto", () => {
  assert.equal(About.probedVersion((major, minor) => major === 6 && minor <= 11, 6), "6.11")
  assert.equal(About.probedVersion((major, minor) => major === 0 && minor <= 3, 0), "0.3")
  assert.equal(About.probedVersion(() => false, 6), "")
  assert.equal(About.probedVersion(null, 6), "")
  const v = { quickshell: "0.3", qt: "6.11", hey: "0.2.2" }
  const details = About.details("0.1.0", v, "Hyprland, wayland")
  assert.equal(details, "HEY Calendar 0.1.0\nQuickshell 0.3, Qt 6.11, HEY CLI 0.2.2\nHyprland, wayland")
  const url = About.mailto("0.1.0", details)
  assert.ok(url.startsWith("mailto:help@ninepointlabs.com?subject=HEY%20Calendar%200.1.0&body="))
  assert.equal(decodeURIComponent(url.split("&body=")[1]), "\n\n--\n" + details)
  assert.equal(About.builtWith({ quickshell: "", qt: "", hey: "" }), "Quickshell and Qt")
})
