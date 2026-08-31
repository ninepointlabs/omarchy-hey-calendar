// Pure JS: date/grid math, HEY CLI command builders, and response parsing for
// the calendar plugin. No QML or Qt types here, so this stays testable under
// node the same way Omarchy's own clock plugin keeps its Model.js pure.

// ---------------------------------------------------------------------------
// Date & grid math — copied from omarchy.clock's Model.js so the Month and
// Year views line up exactly with the native Omarchy calendar popup (same
// week-start handling, same "always six rows" grid, same ISO week numbers).
// ---------------------------------------------------------------------------

var MS_PER_DAY = 86400000
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
var MONTH_NAMES = ["January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"]

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

// Parses a "YYYY-MM-DD" key back into a local Date at midnight.
function dateFromKey(key) {
  var match = String(key || "").match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!match) return null
  return new Date(parseInt(match[1], 10), parseInt(match[2], 10) - 1, parseInt(match[3], 10))
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null
  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null
  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i
  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

// Always six rows of seven days, so the grid never resizes between months.
function monthGrid(year, month, weekStart, todayKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key, year: cellYear, month: cellMonth, day: cellDay, weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    var anchor = thursday || days[0]
    weeks.push({ week: isoWeek(anchor.year, anchor.month, anchor.day), days: days })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

// A single week's seven days, for the Week view. `anchorKey` is any date
// inside the week; the week itself is derived from weekStart the same way
// monthGrid derives its rows.
function weekDays(anchorDate, weekStart, todayKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (anchorDate.getDay() - start + 7) % 7
  var cursor = new Date(anchorDate.getFullYear(), anchorDate.getMonth(), anchorDate.getDate() - leading)
  var today = String(todayKey || "")
  var days = []
  for (var d = 0; d < 7; d++) {
    var key = dateKey(cursor.getFullYear(), cursor.getMonth(), cursor.getDate())
    days.push({
      key: key, year: cursor.getFullYear(), month: cursor.getMonth(), day: cursor.getDate(),
      weekday: cursor.getDay(), weekend: cursor.getDay() === 0 || cursor.getDay() === 6,
      today: key === today
    })
    cursor.setDate(cursor.getDate() + 1)
  }
  return days
}

function stepWeek(anchorDate, delta) {
  var next = new Date(anchorDate.getFullYear(), anchorDate.getMonth(), anchorDate.getDate() + delta * 7)
  return next
}

function monthName(month) {
  return MONTH_NAMES[((Number(month) % 12) + 12) % 12]
}

// ---------------------------------------------------------------------------
// Bounded, hardened process invocation — adapted from 37signals.hey's
// Model.js so `hey` is always run with output size caps, a timeout, and a
// process-group kill on exit rather than inline in every Process element.
// ---------------------------------------------------------------------------

var cliResponseByteLimit = 1024 * 1024
var cliErrorByteLimit = 64 * 1024
var probeResponseByteLimit = 64 * 1024
var finiteCommandTimeoutSec = 30
var finiteCommandKillGraceSec = 2

var boundedCaptureScript = "stdout_limit=$1; stderr_limit=$2; deadline=$3; grace=$4; shift 4; child_pid=; timer_pid=; killer_pid=; timed_out=0; "
  + "stop_timer() { if [ -n \"$timer_pid\" ]; then kill -TERM -- \"-$timer_pid\" 2>/dev/null || true; kill -TERM \"$timer_pid\" 2>/dev/null || true; wait \"$timer_pid\" 2>/dev/null || true; timer_pid=; fi; }; "
  + "start_group_killer() { setpriv --pdeathsig KILL setsid bash -c 'end=$((SECONDS + $1)); while kill -0 -- \"-$2\" 2>/dev/null && [ \"$SECONDS\" -lt \"$end\" ]; do sleep 0.1; done; kill -KILL -- \"-$2\" 2>/dev/null || true' hey-cal-output-killer \"$grace\" \"$child_pid\" & killer_pid=$!; }; "
  + "wait_group_killer() { if [ -n \"$killer_pid\" ]; then wait \"$killer_pid\" 2>/dev/null || true; killer_pid=; fi; }; "
  + "cleanup_group() { if [ -n \"$child_pid\" ] && kill -0 -- \"-$child_pid\" 2>/dev/null; then kill -TERM -- \"-$child_pid\" 2>/dev/null || true; start_group_killer; wait_group_killer; fi; }; "
  + "terminate_child() { if [ -n \"$child_pid\" ]; then kill -TERM -- \"-$child_pid\" 2>/dev/null || true; kill -TERM \"$child_pid\" 2>/dev/null || true; start_group_killer; wait \"$child_pid\" 2>/dev/null || true; wait_group_killer; child_pid=; fi; }; "
  + "stop_child() { trap - HUP INT TERM USR1; stop_timer; terminate_child; exit 143; }; "
  + "trap 'timed_out=1' USR1; trap stop_child HUP INT TERM; "
  + "setpriv --pdeathsig KILL setsid \"$@\" "
  + "> >(head -c \"$((stdout_limit + 1))\") "
  + "2> >(head -c \"$((stderr_limit + 1))\" >&2) & child_pid=$!; "
  + "if [ \"$deadline\" -gt 0 ]; then parent_pid=$BASHPID; "
  + "setpriv --pdeathsig KILL setsid bash -c 'sleep \"$1\" || exit 0; kill -USR1 \"$2\" 2>/dev/null || exit 0; kill -TERM -- \"-$3\" 2>/dev/null || true; kill -TERM \"$3\" 2>/dev/null || true; end=$((SECONDS + $4)); while kill -0 -- \"-$3\" 2>/dev/null && [ \"$SECONDS\" -lt \"$end\" ]; do sleep 0.1; done; if kill -0 -- \"-$3\" 2>/dev/null; then kill -KILL -- \"-$3\" 2>/dev/null || true; fi' "
  + "hey-cal-output-timeout \"$deadline\" \"$parent_pid\" \"$child_pid\" \"$grace\" & timer_pid=$!; fi; "
  + "wait \"$child_pid\"; status=$?; "
  + "if [ \"$timed_out\" -eq 1 ]; then wait \"$child_pid\" 2>/dev/null || true; status=124; wait \"$timer_pid\" 2>/dev/null || true; timer_pid=; "
  + "else stop_timer; cleanup_group; fi; child_pid=; exit \"$status\""

function positiveInteger(value, fallback) {
  var parsed = parseInt(String(value || ""), 10)
  return isFinite(parsed) && parsed > 0 ? parsed : fallback
}

function boundedCaptureCommand(command, stdoutLimit, stderrLimit, timeoutSeconds, killGraceSeconds) {
  var source = Array.isArray(command) ? command : []
  var stdoutBytes = positiveInteger(stdoutLimit, cliResponseByteLimit)
  var stderrBytes = positiveInteger(stderrLimit, cliErrorByteLimit)
  var deadline = timeoutSeconds === 0 ? 0 : positiveInteger(timeoutSeconds, finiteCommandTimeoutSec)
  var grace = positiveInteger(killGraceSeconds, finiteCommandKillGraceSec)
  return ["setpriv", "--pdeathsig", "TERM", "bash", "-o", "pipefail", "-c",
    boundedCaptureScript, "hey-cal-output-guard", String(stdoutBytes), String(stderrBytes),
    String(deadline), String(grace)].concat(source)
}

function shellQuote(value) {
  return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
}

// ---------------------------------------------------------------------------
// Text/JSON bounds — same idea as 37signals.hey: every string surfaced from
// the CLI is length-capped before it reaches a binding.
// ---------------------------------------------------------------------------

var remoteTitleCharacterLimit = 256
var remoteExcerptCharacterLimit = 4000
var remoteNameCharacterLimit = 160
var remoteErrorCharacterLimit = 512
var remoteCodeCharacterLimit = 64
var remoteTypeCharacterLimit = 64

function exceedsUtf8ByteLimit(value, limit) {
  var text = String(value || "")
  var maximum = positiveInteger(limit, cliResponseByteLimit)
  var bytes = 0
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    if (code <= 0x7f) bytes += 1
    else if (code <= 0x7ff) bytes += 2
    else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
        && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) { bytes += 4; i += 1 }
    else bytes += 3
    if (bytes > maximum) return true
  }
  return false
}

function boundedString(value, limit) {
  if (value === undefined || value === null || typeof value === "object") return ""
  var text = String(value)
  var maximum = positiveInteger(limit, remoteExcerptCharacterLimit)
  if (text.length <= maximum) return text
  text = text.substring(0, maximum)
  var last = text.charCodeAt(text.length - 1)
  return last >= 0xd800 && last <= 0xdbff ? text.substring(0, text.length - 1) : text
}

function cleanText(value, limit) {
  var maximum = positiveInteger(limit, remoteExcerptCharacterLimit)
  return boundedString(value, maximum).replace(/\s+/g, " ").trim()
}

function parseJson(raw, byteLimit) {
  var source = String(raw || "")
  if (exceedsUtf8ByteLimit(source, byteLimit || cliResponseByteLimit))
    return { ok: false, error: "The HEY CLI response exceeded its size limit", code: "" }
  var text = source.trim()
  if (text === "") return { ok: false, error: "The HEY CLI returned no data", code: "" }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
      return { ok: false, error: "The HEY CLI returned invalid data", code: "" }
    if (parsed.ok === false) {
      return {
        ok: false,
        error: cleanText(parsed.error || parsed.message || "The HEY CLI request failed", remoteErrorCharacterLimit),
        code: boundedString(parsed.code || "", remoteCodeCharacterLimit)
      }
    }
    return { ok: true, value: parsed }
  } catch (error) {
    return { ok: false, error: "Could not parse the HEY CLI response", code: "" }
  }
}

function parseFailure(stdout, stderr) {
  var hasStderr = String(stderr || "").trim() !== ""
  var text = hasStderr ? stderr : stdout
  var result = parseJson(text, hasStderr ? cliErrorByteLimit : cliResponseByteLimit)
  if (result.ok) return { ok: false, error: "The HEY CLI request failed", code: "" }
  return result
}

function isAuthError(code) {
  var value = boundedString(code || "", remoteCodeCharacterLimit)
  return value === "auth" || value === "auth_required"
}

// ---------------------------------------------------------------------------
// CLI probe / setup — same "is it there, is it new enough, is it signed in"
// one-shot pattern as 37signals.hey, reused verbatim since it is the vetted
// way every other HEY-backed plugin on this system detects setup state.
// ---------------------------------------------------------------------------

var minimumCliVersion = "0.2.2"
var cliTooOldMessage = "HEY CLI " + minimumCliVersion + " or newer is required (omarchy pkg aur add hey-cli)"

var probeCommand = boundedCaptureCommand(
  ["bash", "-c", "command -v hey >/dev/null 2>&1 || { echo missing; exit 0; }; hey --version 2>/dev/null | head -n 1; hey auth status --json"],
  probeResponseByteLimit, cliErrorByteLimit)

function parseProbe(text) {
  var raw = String(text || "")
  if (exceedsUtf8ByteLimit(raw, probeResponseByteLimit)) return { version: "", status: "" }
  var match = raw.match(/^\s*hey version (\S+)[^\n]*\n?/)
  if (!match) return { version: "", status: raw }
  return { version: boundedString(match[1], remoteTypeCharacterLimit), status: raw.substring(match[0].length) }
}

function parseSemver(version) {
  var match = boundedString(version || "", remoteTypeCharacterLimit).trim().match(/^v?(\d+)\.(\d+)\.(\d+)/)
  return match ? [parseInt(match[1], 10), parseInt(match[2], 10), parseInt(match[3], 10)] : null
}

function cliVersionTooOld(version) {
  var parts = parseSemver(version)
  if (!parts) return false
  var minimum = parseSemver(minimumCliVersion)
  for (var i = 0; i < 3; i++) if (parts[i] !== minimum[i]) return parts[i] < minimum[i]
  return false
}

function setupPlan(installed, authenticated) {
  var plan = {
    needed: installed !== true || authenticated !== true,
    title: "Please sign in to HEY",
    command: "hey auth login",
    buttonLabel: "Sign in to HEY…",
    fix: "hey auth login"
  }
  if (installed !== true) {
    plan.title = "HEY CLI is required"
    plan.command = "omarchy pkg aur add hey-cli"
    plan.buttonLabel = "Install HEY CLI…"
    plan.fix = "omarchy-pkg-aur-add hey-cli && hey auth login"
  }
  return plan
}

// ---------------------------------------------------------------------------
// HEY CLI command builders
// ---------------------------------------------------------------------------

function calendarListCommand() {
  return boundedCaptureCommand(["hey", "calendar", "list", "--json"], cliResponseByteLimit, cliErrorByteLimit)
}

function eventListCommand(startsOn, endsOn) {
  return boundedCaptureCommand(
    ["hey", "event", "list", "--starts-on", startsOn, "--ends-on", endsOn, "--json"],
    cliResponseByteLimit, cliErrorByteLimit)
}

function journalListCommand(startsOn, endsOn) {
  return boundedCaptureCommand(
    ["hey", "journal", "list", "--starts-on", startsOn, "--ends-on", endsOn, "--json"],
    cliResponseByteLimit, cliErrorByteLimit)
}

function journalReadCommand(dateKeyValue) {
  return boundedCaptureCommand(["hey", "journal", "read", dateKeyValue, "--json"], cliResponseByteLimit, cliErrorByteLimit)
}

// Empty content removes the entry, per the CLI's own contract — callers must
// route a delete through a confirmation, never send "" by accident. Content
// goes through --content rather than as a bare positional: free-form text
// that happens to start with "-" would otherwise be misread as an unknown
// flag by the CLI's argument parser.
function journalWriteCommand(dateKeyValue, content) {
  return boundedCaptureCommand(["hey", "journal", "write", dateKeyValue, "--content", String(content || "")],
    cliResponseByteLimit, cliErrorByteLimit)
}

// Title goes through --title rather than as a bare positional, for the same
// leading-dash reason as journalWriteCommand above.
function eventAddCommand(fields) {
  var args = ["hey", "event", "add", "--title", String(fields.title || "").trim()]
  if (fields.date) args.push("--starts-on", fields.date)
  if (fields.allDay) {
    args.push("--all-day")
  } else {
    if (fields.startTime) args.push("--start-time", fields.startTime)
    if (fields.endTime) args.push("--end-time", fields.endTime)
  }
  if (fields.calendarId) args.push("--calendar", String(fields.calendarId))
  if (fields.location) args.push("--location", fields.location)
  args.push("--json")
  return boundedCaptureCommand(args, cliResponseByteLimit, cliErrorByteLimit)
}

// `id` and the optional narrowing `[date]` are positional and must precede
// the flags per the CLI's own usage line (`hey event edit <id> [date]
// [flags]`) — only the flags named here change; HEY preserves everything
// else on the event, which is why an edit never resends fields the UI
// doesn't expose (notes, reminders, calendar, ...).
function eventEditCommand(id, fields) {
  var args = ["hey", "event", "edit", String(id)]
  if (fields.date !== undefined) args.push(String(fields.date))
  if (fields.title !== undefined) args.push("--title", String(fields.title))
  if (fields.allDay === true) args.push("--all-day")
  if (fields.startTime !== undefined) args.push("--start-time", String(fields.startTime))
  if (fields.endTime !== undefined) args.push("--end-time", String(fields.endTime))
  if (fields.location !== undefined) args.push("--location", String(fields.location))
  args.push("--json")
  return boundedCaptureCommand(args, cliResponseByteLimit, cliErrorByteLimit)
}

function eventDeleteCommand(id) {
  return boundedCaptureCommand(["hey", "event", "delete", String(id), "--json"], cliResponseByteLimit, cliErrorByteLimit)
}

// Shell one-liner for the "Open in editor" journal handoff: drops into
// `hey journal write DATE` with no content, which the CLI itself opens in
// $EDITOR, then calls back into the panel over IPC so the entry refreshes
// the moment the editor closes — the same trap-on-EXIT idiom 37signals.hey
// uses to report its own setup flow's completion.
function journalEditLaunchCommand(dateKeyValue, ipcTarget) {
  var date = shellQuote(dateKeyValue)
  var target = shellQuote(ipcTarget)
  return "trap 'rc=$?; trap - EXIT; omarchy-shell -q " + target + " journalEditFinished >/dev/null 2>&1 || true; exit $rc' EXIT; hey journal write " + date
}

// ---------------------------------------------------------------------------
// Response parsing / normalization
// ---------------------------------------------------------------------------

function parseCalendars(raw) {
  var result = parseJson(raw)
  if (!result.ok) return { ok: false, error: result.error, calendars: [] }
  var data = Array.isArray(result.value.data) ? result.value.data : []
  var calendars = []
  for (var i = 0; i < data.length && calendars.length < 64; i++) {
    var entry = data[i] || {}
    var id = entry.id
    if (id === undefined || id === null) continue
    calendars.push({
      id: String(id),
      name: cleanText(entry.name || (entry.personal ? "Personal" : "Calendar"), remoteNameCharacterLimit),
      color: cleanText(entry.color || "", 32),
      personal: entry.personal === true
    })
  }
  return { ok: true, error: "", calendars: calendars }
}

// A palette index per calendar id, stable for the session — used when a
// calendar has no `color` string from HEY (the personal calendar usually
// doesn't) so its events still get a consistent dot color.
function calendarColorIndex(calendarId, count) {
  var total = Number(count || 0)
  if (!isFinite(total) || total <= 0) return 0
  var text = String(calendarId || "")
  var hash = 5381
  for (var i = 0; i < text.length; i++) hash = ((hash * 33) ^ text.charCodeAt(i)) >>> 0
  return hash % total
}

function localDateKeyFromIso(iso) {
  var value = String(iso || "")
  if (value === "") return ""
  var parsed = new Date(value)
  if (isNaN(parsed.getTime())) return ""
  return keyForDate(parsed)
}

function normalizeEvent(value) {
  var raw = value && typeof value === "object" ? value : {}
  var id = raw.id
  if (id === undefined || id === null) return null
  var startsAt = boundedString(raw.starts_at || "", 64)
  var endsAt = boundedString(raw.ends_at || "", 64)
  var calendar = raw.calendar && typeof raw.calendar === "object" ? raw.calendar : {}
  return {
    id: String(id),
    title: cleanText(raw.title || raw.summary || "Untitled event", remoteTitleCharacterLimit),
    description: cleanText(raw.description || "", remoteExcerptCharacterLimit),
    location: cleanText(raw.location || "", remoteNameCharacterLimit),
    startsAt: startsAt,
    endsAt: endsAt,
    startsDateKey: localDateKeyFromIso(startsAt),
    endsDateKey: localDateKeyFromIso(endsAt || startsAt),
    allDay: raw.all_day === true,
    recurring: raw.recurring === true,
    calendarId: calendar.id !== undefined && calendar.id !== null ? String(calendar.id) : "",
    calendarName: cleanText(calendar.name || "", remoteNameCharacterLimit),
    calendarColor: cleanText(calendar.color || "", 32)
  }
}

function parseEvents(raw) {
  var result = parseJson(raw)
  if (!result.ok) return { ok: false, error: result.error, events: [] }
  var data = Array.isArray(result.value.data) ? result.value.data : []
  var events = []
  for (var i = 0; i < data.length && events.length < 2000; i++) {
    var event = normalizeEvent(data[i])
    if (event) events.push(event)
  }
  events.sort(function(a, b) {
    if (a.allDay !== b.allDay) return a.allDay ? -1 : 1
    return String(a.startsAt).localeCompare(String(b.startsAt))
  })
  return { ok: true, error: "", events: events }
}

// hey journal list returns entries with (at minimum) a `date`; used only to
// know which days have an entry, for pip dots — not to read the content.
function parseJournalDays(raw) {
  var result = parseJson(raw)
  if (!result.ok) return { ok: false, error: result.error, days: {} }
  var data = Array.isArray(result.value.data) ? result.value.data : []
  var days = {}
  for (var i = 0; i < data.length && i < 2000; i++) {
    var entry = data[i] || {}
    var key = boundedString(entry.date || entry.day || "", 10)
    if (/^\d{4}-\d{2}-\d{2}$/.test(key)) days[key] = true
  }
  return { ok: true, error: "", days: days }
}

// hey journal read answers `{ok:true, summary:"No journal entry for DATE"}`
// with no `data` when the day is empty, and otherwise carries the entry
// under `data` — as a string, or an object with a content/markdown field
// depending on CLI version. Both shapes are handled defensively.
function parseJournalEntry(raw) {
  var result = parseJson(raw)
  if (!result.ok) return { ok: false, error: result.error, exists: false, content: "" }
  var data = result.value.data
  if (data === undefined || data === null) return { ok: true, error: "", exists: false, content: "" }
  if (typeof data === "string") return { ok: true, error: "", exists: data.trim() !== "", content: data }
  if (typeof data === "object") {
    var content = data.content || data.markdown || data.body || data.text || ""
    return { ok: true, error: "", exists: String(content).trim() !== "", content: String(content) }
  }
  return { ok: true, error: "", exists: false, content: "" }
}

// Groups a flat event list by local start-date key, for grid pip dots and
// per-day agendas. Multi-day / all-day spans are attributed to their start
// day only — HEY CLI does not expose per-occurrence spans to expand further.
function eventsByDay(events) {
  var byDay = {}
  var source = Array.isArray(events) ? events : []
  for (var i = 0; i < source.length; i++) {
    var event = source[i]
    var key = event.startsDateKey
    if (key === "") continue
    if (!byDay[key]) byDay[key] = []
    byDay[key].push(event)
  }
  return byDay
}

function eventsOnDay(events, key) {
  var source = Array.isArray(events) ? events : []
  var out = []
  for (var i = 0; i < source.length; i++) if (source[i].startsDateKey === key) out.push(source[i])
  return out
}

// "3:45pm" from an ISO instant, in the local zone; "" for an all-day event.
function eventTimeLabel(event) {
  if (!event || event.allDay) return ""
  var date = new Date(event.startsAt)
  if (isNaN(date.getTime())) return ""
  var hours = date.getHours()
  var hour12 = hours % 12 === 0 ? 12 : hours % 12
  var minutes = date.getMinutes()
  return hour12 + (minutes === 0 ? "" : ":" + (minutes < 10 ? "0" + minutes : minutes)) + (hours >= 12 ? "pm" : "am")
}

function eventTimeRangeLabel(event) {
  if (!event) return ""
  if (event.allDay) return "All day"
  var start = eventTimeLabel(event)
  if (!event.endsAt || event.endsAt === event.startsAt) return start
  var end = new Date(event.endsAt)
  if (isNaN(end.getTime())) return start
  var startDate = new Date(event.startsAt)
  var sameDay = !isNaN(startDate.getTime()) && keyForDate(startDate) === keyForDate(end)
  if (!sameDay) return start
  var hours = end.getHours()
  var hour12 = hours % 12 === 0 ? 12 : hours % 12
  var minutes = end.getMinutes()
  var endLabel = hour12 + (minutes === 0 ? "" : ":" + (minutes < 10 ? "0" + minutes : minutes)) + (hours >= 12 ? "pm" : "am")
  return start + " – " + endLabel
}

// The next upcoming event today (or, failing that, the very next one) for
// the bar widget's "next event" label.
function nextEventLabel(events, nowMs) {
  var source = Array.isArray(events) ? events : []
  var now = Number(nowMs || Date.now())
  var best = null
  for (var i = 0; i < source.length; i++) {
    var event = source[i]
    var startMs = Date.parse(event.startsAt)
    if (!isFinite(startMs) || startMs < now - 60000) continue
    if (best === null || startMs < Date.parse(best.startsAt)) best = event
  }
  if (!best) return ""
  var time = eventTimeLabel(best)
  return time === "" ? best.title : time + " · " + best.title
}

// Validates a 24h "HH:MM" field before it reaches a command line.
function validTimeOfDay(value) {
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(String(value || "").trim())
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey, keyForDate: keyForDate, dateFromKey: dateFromKey,
    normalizedWeekStart: normalizedWeekStart, weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart, weekdayOrder: weekdayOrder, isoWeek: isoWeek,
    monthGrid: monthGrid, stepMonth: stepMonth, weekDays: weekDays, stepWeek: stepWeek,
    monthName: monthName,
    boundedCaptureCommand: boundedCaptureCommand, shellQuote: shellQuote,
    cliResponseByteLimit: cliResponseByteLimit, cliErrorByteLimit: cliErrorByteLimit,
    probeResponseByteLimit: probeResponseByteLimit,
    boundedString: boundedString, cleanText: cleanText, exceedsUtf8ByteLimit: exceedsUtf8ByteLimit,
    parseJson: parseJson, parseFailure: parseFailure, isAuthError: isAuthError,
    minimumCliVersion: minimumCliVersion, cliTooOldMessage: cliTooOldMessage,
    probeCommand: probeCommand, parseProbe: parseProbe, cliVersionTooOld: cliVersionTooOld,
    setupPlan: setupPlan,
    calendarListCommand: calendarListCommand, eventListCommand: eventListCommand,
    journalListCommand: journalListCommand, journalReadCommand: journalReadCommand,
    journalWriteCommand: journalWriteCommand, eventAddCommand: eventAddCommand,
    eventEditCommand: eventEditCommand, eventDeleteCommand: eventDeleteCommand,
    journalEditLaunchCommand: journalEditLaunchCommand,
    parseCalendars: parseCalendars, calendarColorIndex: calendarColorIndex,
    parseEvents: parseEvents, parseJournalDays: parseJournalDays, parseJournalEntry: parseJournalEntry,
    eventsByDay: eventsByDay, eventsOnDay: eventsOnDay,
    eventTimeLabel: eventTimeLabel, eventTimeRangeLabel: eventTimeRangeLabel,
    nextEventLabel: nextEventLabel, validTimeOfDay: validTimeOfDay
  }
}
