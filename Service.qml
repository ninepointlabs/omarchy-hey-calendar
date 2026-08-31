import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The plugin's data layer, instantiated once per shell as its `service`
// entry point — every bar widget (one per monitor) and every open panel
// reads this one instance, so switching months or opening a day never fires
// more than one `hey` process at a time. Panels push their settings in,
// since the shell injects settings into widgets only (see 37signals.hey for
// the same pattern).
Item {
  id: root

  property var shell: null
  property var settings: ({})
  // A widget-local instance, built only under a shell without service
  // support, stays inert once a shared one exists.
  property bool active: true

  // ---- CLI setup state
  property bool installed: true
  property bool authenticated: true
  property bool cliOutdated: false
  property bool probed: false
  property bool probeError: false
  property bool probing: false
  property string lastError: ""

  // ---- Calendars (for color-coding; fetched once per probe cycle)
  property var calendars: []

  // ---- The currently requested date window (Today/Week/Month/Year all
  //      funnel through this — the panel asks for whatever window its
  //      active view needs, and the service owns exactly one in flight).
  property string windowStart: ""
  property string windowEnd: ""
  property var windowEvents: []
  property var journalDays: ({})
  property bool windowLoading: false
  property string windowError: ""
  property double windowLoadedAtMs: 0

  // ---- Day detail: the journal entry for whichever day is currently open,
  //      keyed so a stale response for a day the user has since left can't
  //      clobber the one they're looking at.
  property string openDayKey: ""
  property bool journalLoading: false
  property string journalError: ""
  property bool journalExists: false
  property string journalContent: ""

  // ---- Mutations (add/edit/delete event, write journal) — one at a time,
  //      surfaced as a short-lived status line the same way 37signals.hey
  //      reports "Marked as seen".
  property bool mutating: false
  property string actionStatus: ""
  property string actionError: ""

  readonly property bool busy: probing || windowLoading || journalLoading || mutating

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function conciseError(value, fallback) {
    var text = Model.cleanText(value || fallback || "HEY request failed", Model.cliErrorByteLimit)
    return text.length > 200 ? text.substring(0, 197) + "…" : text
  }

  // -------------------------------------------------------------- Probe --

  function refresh() {
    if (!active || probing) return
    probing = true
    lastError = ""
    _probeOut = ""
    _probeErr = ""
    probeProcess.running = true
  }

  function refreshIfStale() {
    if (windowLoadedAtMs <= 0 || Date.now() - windowLoadedAtMs >= 300000) refresh()
  }

  property string _probeOut: ""
  property string _probeErr: ""

  Process {
    id: probeProcess
    running: false
    command: Model.probeCommand
    stdout: StdioCollector { id: probeStdout; waitForEnd: true; onStreamFinished: root._probeOut = text }
    stderr: StdioCollector { id: probeStderr; waitForEnd: true; onStreamFinished: root._probeErr = text }
    onExited: function(exitCode) {
      root.finishProbe(String(probeStdout.text || root._probeOut || ""), String(probeStderr.text || root._probeErr || ""))
    }
  }

  function finishProbe(stdoutText, stderrText) {
    probed = true
    probeError = false
    probing = false
    var text = String(stdoutText || "")
    if (text.trim() === "missing") {
      installed = false
      authenticated = true
      return
    }
    installed = true

    var probe = Model.parseProbe(text)
    cliOutdated = Model.cliVersionTooOld(probe.version)
    if (cliOutdated) {
      lastError = Model.cliTooOldMessage
      return
    }

    var result = Model.parseJson(probe.status)
    if (!result.ok || !result.value.data) {
      authenticated = true
      probeError = true
      lastError = conciseError(stderrText || (result.error || "unexpected response"), "Could not check the HEY CLI")
      return
    }
    authenticated = result.value.data.authenticated === true
    if (!authenticated) return

    loadCalendars()
    if (windowStart !== "" && windowEnd !== "") requestWindow(windowStart, windowEnd, true)
  }

  // ---------------------------------------------------------- Calendars --

  property string _calendarsOut: ""
  property string _calendarsErr: ""

  function loadCalendars() {
    _calendarsOut = ""
    _calendarsErr = ""
    calendarsProcess.running = true
  }

  Process {
    id: calendarsProcess
    running: false
    command: Model.calendarListCommand()
    stdout: StdioCollector { id: calendarsStdout; waitForEnd: true; onStreamFinished: root._calendarsOut = text }
    stderr: StdioCollector { id: calendarsStderr; waitForEnd: true; onStreamFinished: root._calendarsErr = text }
    onExited: function(exitCode) {
      var stdout = String(calendarsStdout.text || root._calendarsOut || "")
      var stderr = String(calendarsStderr.text || root._calendarsErr || "")
      if (exitCode !== 0) {
        if (Model.isAuthError(Model.parseFailure(stdout, stderr).code)) { root.authenticated = false; return }
        root.lastError = root.conciseError(Model.parseFailure(stdout, stderr).error || stderr, "Could not list HEY calendars")
        return
      }
      var parsed = Model.parseCalendars(stdout)
      if (parsed.ok) root.calendars = parsed.calendars
    }
  }

  // -------------------------------------------------------------- Window --

  // Asks for a date window (Today/Week/Month/Year all resolve to one of
  // these before calling in). `force` re-fetches even if the window is
  // unchanged — used after a mutation invalidates the cached data.
  function requestWindow(startKey, endKey, force) {
    if (!active) return
    if (!force && startKey === windowStart && endKey === windowEnd && windowLoadedAtMs > 0) return
    windowStart = startKey
    windowEnd = endKey
    if (!probed || !installed || !authenticated || cliOutdated) return
    windowLoading = true
    windowError = ""
    _eventsOut = ""
    _eventsErr = ""
    _journalDaysOut = ""
    _journalDaysErr = ""
    _windowPending = 2
    eventsProcess.command = Model.eventListCommand(startKey, endKey)
    eventsProcess.running = true
    journalDaysProcess.command = Model.journalListCommand(startKey, endKey)
    journalDaysProcess.running = true
  }

  property int _windowPending: 0
  property string _eventsOut: ""
  property string _eventsErr: ""
  property string _journalDaysOut: ""
  property string _journalDaysErr: ""

  function _windowStepDone() {
    _windowPending -= 1
    if (_windowPending <= 0) {
      windowLoading = false
      windowLoadedAtMs = Date.now()
    }
  }

  Process {
    id: eventsProcess
    running: false
    command: []
    stdout: StdioCollector { id: eventsStdout; waitForEnd: true; onStreamFinished: root._eventsOut = text }
    stderr: StdioCollector { id: eventsStderr; waitForEnd: true; onStreamFinished: root._eventsErr = text }
    onExited: function(exitCode) {
      var stdout = String(eventsStdout.text || root._eventsOut || "")
      var stderr = String(eventsStderr.text || root._eventsErr || "")
      if (exitCode !== 0) {
        if (Model.isAuthError(Model.parseFailure(stdout, stderr).code)) { root.authenticated = false; root._windowStepDone(); return }
        root.windowError = root.conciseError(Model.parseFailure(stdout, stderr).error || stderr, "Could not load events")
        root._windowStepDone()
        return
      }
      var parsed = Model.parseEvents(stdout)
      if (parsed.ok) root.windowEvents = parsed.events
      else root.windowError = parsed.error
      root._windowStepDone()
    }
  }

  Process {
    id: journalDaysProcess
    running: false
    command: []
    stdout: StdioCollector { id: journalDaysStdout; waitForEnd: true; onStreamFinished: root._journalDaysOut = text }
    stderr: StdioCollector { id: journalDaysStderr; waitForEnd: true; onStreamFinished: root._journalDaysErr = text }
    onExited: function(exitCode) {
      var stdout = String(journalDaysStdout.text || root._journalDaysOut || "")
      var stderr = String(journalDaysStderr.text || root._journalDaysErr || "")
      if (exitCode !== 0) {
        // Non-fatal: pip dots for journal days are a bonus, not core data.
        root._windowStepDone()
        return
      }
      var parsed = Model.parseJournalDays(stdout)
      if (parsed.ok) root.journalDays = parsed.days
      root._windowStepDone()
    }
  }

  // ---------------------------------------------------------- Day detail --

  function openDay(dateKeyValue) {
    openDayKey = dateKeyValue
    fetchJournalEntry(dateKeyValue)
  }

  property string _journalEntryOut: ""
  property string _journalEntryErr: ""
  property string _journalEntryRequestedKey: ""

  function fetchJournalEntry(dateKeyValue) {
    if (!probed || !installed || !authenticated || cliOutdated) return
    journalLoading = true
    journalError = ""
    _journalEntryRequestedKey = dateKeyValue
    _journalEntryOut = ""
    _journalEntryErr = ""
    journalEntryProcess.command = Model.journalReadCommand(dateKeyValue)
    journalEntryProcess.running = true
  }

  Process {
    id: journalEntryProcess
    running: false
    command: []
    stdout: StdioCollector { id: journalEntryStdout; waitForEnd: true; onStreamFinished: root._journalEntryOut = text }
    stderr: StdioCollector { id: journalEntryStderr; waitForEnd: true; onStreamFinished: root._journalEntryErr = text }
    onExited: function(exitCode) {
      var stdout = String(journalEntryStdout.text || root._journalEntryOut || "")
      var stderr = String(journalEntryStderr.text || root._journalEntryErr || "")
      // A response for a day the user has since navigated away from is
      // dropped rather than shown against the wrong header.
      if (root._journalEntryRequestedKey !== root.openDayKey) { root.journalLoading = false; return }
      if (exitCode !== 0) {
        root.journalLoading = false
        if (Model.isAuthError(Model.parseFailure(stdout, stderr).code)) { root.authenticated = false; return }
        root.journalError = root.conciseError(Model.parseFailure(stdout, stderr).error || stderr, "Could not read journal entry")
        return
      }
      var parsed = Model.parseJournalEntry(stdout)
      root.journalLoading = false
      root.journalExists = parsed.exists
      root.journalContent = parsed.content
    }
  }

  // -------------------------------------------------------------- Mutate --

  property string _mutationOut: ""
  property string _mutationErr: ""
  property string _mutationKind: ""

  function _runMutation(kind, command) {
    if (mutating) return false
    mutating = true
    actionStatus = ""
    actionError = ""
    _mutationKind = kind
    _mutationOut = ""
    _mutationErr = ""
    mutationProcess.command = command
    mutationProcess.running = true
    return true
  }

  function addEvent(fields) {
    return _runMutation("add", Model.eventAddCommand(fields))
  }

  function editEvent(id, fields) {
    return _runMutation("edit", Model.eventEditCommand(id, fields))
  }

  function deleteEvent(id) {
    return _runMutation("delete", Model.eventDeleteCommand(id))
  }

  // Writing empty content removes the entry — callers must confirm deletion
  // before calling this with "".
  function writeJournal(dateKeyValue, content) {
    return _runMutation("journal", Model.journalWriteCommand(dateKeyValue, content))
  }

  readonly property var _mutationLabels: ({
    add: { ok: "Event added", fail: "Could not add event" },
    edit: { ok: "Event updated", fail: "Could not update event" },
    "delete": { ok: "Event deleted", fail: "Could not delete event" },
    journal: { ok: "Journal saved", fail: "Could not save journal entry" }
  })

  Process {
    id: mutationProcess
    running: false
    command: []
    stdout: StdioCollector { id: mutationStdout; waitForEnd: true; onStreamFinished: root._mutationOut = text }
    stderr: StdioCollector { id: mutationStderr; waitForEnd: true; onStreamFinished: root._mutationErr = text }
    onExited: function(exitCode) {
      var stdout = String(mutationStdout.text || root._mutationOut || "")
      var stderr = String(mutationStderr.text || root._mutationErr || "")
      var labels = root._mutationLabels[root._mutationKind] || { ok: "Saved", fail: "Request failed" }
      root.mutating = false
      if (exitCode !== 0) {
        if (Model.isAuthError(Model.parseFailure(stdout, stderr).code)) { root.authenticated = false; return }
        root.actionError = root.conciseError(Model.parseFailure(stdout, stderr).error || stderr, labels.fail)
        actionStatusTimer.restart()
        return
      }
      root.actionStatus = labels.ok
      actionStatusTimer.restart()

      // Refresh whatever the mutation could have changed: the visible
      // window always, and the open day's journal when it was a journal
      // write for that same day.
      if (root.windowStart !== "" && root.windowEnd !== "") root.requestWindow(root.windowStart, root.windowEnd, true)
      if (root._mutationKind === "journal" && root.openDayKey !== "") root.fetchJournalEntry(root.openDayKey)
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2500
    repeat: false
    onTriggered: { root.actionStatus = ""; root.actionError = "" }
  }

  Timer {
    id: refreshTimer
    interval: 300000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onActiveChanged: if (active && !probed) refresh()
}
