import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The calendar panel: Today/Week/Month/Year view switcher, plus a day-detail
// overlay (events + journal) opened by clicking any day in Week/Month/Year.
// Today embeds that same detail content directly since it's the landing view.
//
// IPC lives on BarWidget.qml (the clock plugin's split), not here — this
// component only needs moduleName so the shell can inject bar/settings/
// anchorItem/hostWidget into it.
Panel {
  id: root
  moduleName: "tim.hey-calendar"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)
  readonly property int weekStart: Model.normalizedWeekStart(null, Qt.locale().firstDayOfWeek)

  property string currentView: setting("view", "month")
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  property date weekAnchor: today

  property bool dayDetailOpen: false
  property string dayDetailKey: ""
  readonly property date dayDetailDate: dayDetailKey !== "" ? (Model.dateFromKey(dayDetailKey) || today) : today

  // One service per shell — every bar widget and every open panel reads the
  // same instance, so switching views never fires more than one `hey`
  // process at a time. A shell without service support gets a local one.
  readonly property var sharedService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var service: sharedService || localService

  function pushSettings() { if (service) service.settings = settings }
  onSettingsChanged: pushSettings()
  onServiceChanged: { pushSettings(); updateWindow() }
  Component.onCompleted: pushSettings()

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  function computeEventDayKeys() {
    var byDay = Model.eventsByDay(service ? service.windowEvents : [])
    var out = ({})
    for (var k in byDay) out[k] = true
    return out
  }
  readonly property var eventDayKeys: computeEventDayKeys()
  readonly property var journalDayKeys: service ? service.journalDays : ({})

  function dayEvents(key) {
    return Model.eventsOnDay(service ? service.windowEvents : [], key)
  }

  function computeCalendarOptions() {
    var cals = service ? service.calendars : []
    var out = []
    for (var i = 0; i < cals.length; i++) out.push({ value: cals[i].id, label: cals[i].name })
    return out
  }
  readonly property var calendarOptions: computeCalendarOptions()

  // ---------------------------------------------------------- Navigation --

  function updateWindow() {
    if (!service) return
    if (currentView === "today") {
      service.requestWindow(todayKey, todayKey, false)
    } else if (currentView === "week") {
      var days = Model.weekDays(weekAnchor, weekStart, todayKey)
      service.requestWindow(days[0].key, days[6].key, false)
    } else if (currentView === "month") {
      var weeks = Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)
      service.requestWindow(weeks[0].days[0].key, weeks[weeks.length - 1].days[6].key, false)
    } else if (currentView === "year") {
      service.requestWindow(viewYear + "-01-01", viewYear + "-12-31", false)
    }
  }

  onCurrentViewChanged: {
    updateWindow()
    if (currentView === "today" && service) service.openDay(todayKey)
  }
  onViewYearChanged: updateWindow()
  onViewMonthChanged: updateWindow()
  onWeekAnchorChanged: updateWindow()

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setView(name) {
    if (currentView === name) {
      goToToday()
      return
    }
    currentView = name
    persistSettings({ view: name })
  }

  function goToToday() {
    viewYear = today.getFullYear()
    viewMonth = today.getMonth()
    weekAnchor = today
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    viewYear = next.year
    viewMonth = next.month
  }

  function moveWeek(delta) { weekAnchor = Model.stepWeek(weekAnchor, delta) }
  function moveYear(delta) { viewYear += delta }

  function openDay(key) {
    dayDetailKey = key
    dayDetailOpen = true
    if (service) service.openDay(key)
    Qt.callLater(function() { if (dayDetailFlick) dayDetailFlick.contentY = 0 })
  }

  function closeDayDetail() {
    dayDetailOpen = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    root.today = new Date()
    if (service) service.refresh()
    updateWindow()
    if (root.currentView === "today" && service) service.openDay(root.todayKey)
    else if (root.dayDetailOpen && service) service.fetchJournalEntry(root.dayDetailKey)
  }

  function launchSetup() {
    if (!bar || !service) return
    bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(setupPlanValue.fix))
    close()
  }

  function openJournalEditor(dateKeyValue) {
    if (!bar || !hostWidget) return
    var command = Model.journalEditLaunchCommand(dateKeyValue, hostWidget.moduleName)
    bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(command))
  }

  readonly property var setupPlanValue: Model.setupPlan(service ? service.installed : true, service ? service.authenticated : true)
  readonly property bool needsSetup: service && service.probed && setupPlanValue.needed

  readonly property string statusText: {
    if (!service) return ""
    if (service.actionError !== "") return service.actionError
    if (service.actionStatus !== "") return service.actionStatus
    if (service.windowError !== "") return service.windowError
    if (service.lastError !== "") return service.lastError
    return ""
  }
  readonly property bool statusIsError: service && (service.actionError !== "" || service.windowError !== "" || service.lastError !== "")

  implicitWidth: 1
  implicitHeight: 1

  onOpenedChanged: {
    if (!opened) {
      dayDetailOpen = false
      // Reset navigation to today on close, not just on an explicit "Today"
      // click — otherwise the bar widget's "next event" label would keep
      // reading whatever month/week/year was last browsed to, since it and
      // the panel share one fetched window.
      goToToday()
      return
    }
    today = new Date()
    if (service) service.refreshIfStale()
    updateWindow()
    if (currentView === "today" && service) service.openDay(todayKey)
    if (mainFlick) mainFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: localService
    active: root.sharedService === null
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      root.today = date
      if (root.currentView === "today") {
        root.updateWindow()
        if (root.service) root.service.openDay(root.todayKey)
      }
    }
  }

  // Auto-retry while CLI setup is showing, the same 3s probe cadence
  // 37signals.hey uses.
  Timer {
    interval: 3000
    repeat: true
    running: root.opened && root.needsSetup
    onTriggered: if (root.service) root.service.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(620))
    contentHeight: panel.fittedContentHeight(
      root.dayDetailOpen
        ? dayDetailInner.implicitHeight + Style.space(24)
        : fixedContent.implicitHeight + mainColumn.implicitHeight + Style.space(24),
      Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.dayDetailOpen
      onMoveRequested: function(dx, dy) {
        if (root.currentView === "month") { if (dx !== 0) root.moveMonth(dx); if (dy !== 0) root.moveYear(dy) }
        else if (root.currentView === "week" && dx !== 0) root.moveWeek(dx)
        else if (root.currentView === "year" && dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") root.goToToday()
        else if (t === "r" || t === "R") root.refresh()
        else if (t === "1") root.setView("today")
        else if (t === "2") root.setView("week")
        else if (t === "3") root.setView("month")
        else if (t === "4") root.setView("year")
      }

      // ---------------------------------------------------------- Main --
      ColumnLayout {
        id: content
        anchors.fill: parent
        visible: !root.dayDetailOpen
        spacing: Style.space(12)

        Column {
          id: fixedContent
          Layout.fillWidth: true
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: Math.max(titleColumn.implicitHeight, refreshButton.implicitHeight)

            Column {
              id: titleColumn
              anchors.left: parent.left
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(2)

              Text {
                text: "HEY CALENDAR"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                visible: text !== ""
                width: parent.width
                text: root.statusText
                textFormat: Text.PlainText
                color: root.statusIsError ? Color.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: service && service.busy ? "󰑓" : "󰑐"
              tooltipText: "Refresh"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !service || !service.busy
              onClicked: root.refresh()
            }
          }

          PanelSeparator { foreground: root.foreground }

          Row {
            visible: !root.needsSetup
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: [
                { key: "today", label: "TODAY" },
                { key: "week", label: "WEEK" },
                { key: "month", label: "MONTH" },
                { key: "year", label: "YEAR" }
              ]

              Button {
                required property var modelData
                text: modelData.label
                selected: root.currentView === modelData.key
                foreground: root.foreground
                background: "transparent"
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(9)
                verticalPadding: Style.space(3)
                onClicked: root.setView(modelData.key)
              }
            }
          }

          // ---- Context nav: month/year steppers, or the week's span.
          Item {
            visible: !root.needsSetup && root.currentView !== "today"
            width: parent.width
            height: navRow.implicitHeight + Style.space(6)

            Item {
              id: navRow
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(220)
              implicitHeight: navLabel.implicitHeight

              Text {
                id: navLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                  if (root.currentView === "month") return Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy").toUpperCase()
                  if (root.currentView === "year") return String(root.viewYear)
                  if (root.currentView === "week") {
                    var days = Model.weekDays(root.weekAnchor, root.weekStart, root.todayKey)
                    return Qt.formatDate(Model.dateFromKey(days[0].key), "MMM d") + " – " + Qt.formatDate(Model.dateFromKey(days[6].key), "MMM d")
                  }
                  return ""
                }
                color: Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: {
                  if (root.currentView === "month") root.moveMonth(-1)
                  else if (root.currentView === "week") root.moveWeek(-1)
                  else if (root.currentView === "year") root.moveYear(-1)
                }
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: {
                  if (root.currentView === "month") root.moveMonth(1)
                  else if (root.currentView === "week") root.moveWeek(1)
                  else if (root.currentView === "year") root.moveYear(1)
                }
              }
            }
          }
        }

        Flickable {
          id: mainFlick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: mainColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: mainColumn
            width: mainFlick.width
            spacing: Style.space(10)

            // ---- Setup prompt (CLI missing / signed out)
            Column {
              visible: root.needsSetup
              width: parent.width
              spacing: Style.space(8)
              topPadding: Style.space(16)
              bottomPadding: Style.space(18)

              Text {
                width: parent.width
                text: root.setupPlanValue.title
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
              }

              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.setupPlanValue.buttonLabel
                bordered: true
                foreground: root.foreground
                background: Color.popups.background
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.launchSetup()
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "or run: " + root.setupPlanValue.command
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // ---- Today: the day-detail content, embedded
            DayDetail {
              visible: !root.needsSetup && root.currentView === "today"
              width: parent.width
              dayDate: root.today
              dateKey: root.todayKey
              events: root.dayEvents(root.todayKey)
              service: root.service
              calendarOptions: root.calendarOptions
              embedded: true
              foreground: root.foreground
              accent: root.accent
              background: Color.popups.background
              fontFamily: root.fontFamily
              onOpenJournalEditorRequested: function(dateKeyValue) { root.openJournalEditor(dateKeyValue) }
            }

            // ---- Week: seven compact agenda rows
            Column {
              visible: !root.needsSetup && root.currentView === "week"
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: Model.weekDays(root.weekAnchor, root.weekStart, root.todayKey)

                Rectangle {
                  id: weekRow
                  required property var modelData
                  readonly property var rowEvents: root.dayEvents(modelData.key)
                  width: parent.width
                  height: rowContent.implicitHeight + Style.space(14)
                  radius: Style.cornerRadius
                  color: weekMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
                  border.width: modelData.today ? Style.spacing.hairline : 0
                  border.color: Style.normalBorderFor(root.foreground, root.accent)

                  Row {
                    id: rowContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Style.space(10)
                    spacing: Style.space(10)

                    Column {
                      width: Style.space(56)
                      spacing: Style.space(1)

                      Text {
                        textFormat: Text.PlainText
                        text: Qt.formatDate(Model.dateFromKey(weekRow.modelData.key), "ddd").toUpperCase()
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: weekRow.modelData.day
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        font.bold: weekRow.modelData.today
                      }
                    }

                    Column {
                      width: parent.width - Style.space(76)
                      spacing: Style.space(2)

                      Text {
                        visible: weekRow.rowEvents.length === 0
                        text: "Nothing scheduled"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      Repeater {
                        model: weekRow.rowEvents.slice(0, 3)

                        Text {
                          required property var modelData
                          textFormat: Text.PlainText
                          width: parent.width
                          text: (Model.eventTimeLabel(modelData) !== "" ? Model.eventTimeLabel(modelData) + " · " : "") + modelData.title
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          elide: Text.ElideRight
                        }
                      }

                      Text {
                        visible: weekRow.rowEvents.length > 3
                        text: "+" + (weekRow.rowEvents.length - 3) + " more"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  MouseArea {
                    id: weekMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDay(weekRow.modelData.key)
                  }
                }
              }
            }

            // ---- Month: one grid
            MonthGrid {
              visible: !root.needsSetup && root.currentView === "month"
              anchors.horizontalCenter: parent.horizontalCenter
              year: root.viewYear
              month: root.viewMonth
              weekStart: root.weekStart
              todayKey: root.todayKey
              eventDayKeys: root.eventDayKeys
              journalDayKeys: root.journalDayKeys
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onDayClicked: function(dateKeyValue) { root.openDay(dateKeyValue) }
              onMonthLabelClicked: root.goToToday()
            }

            // ---- Year: twelve compact grids
            Grid {
              visible: !root.needsSetup && root.currentView === "year"
              anchors.horizontalCenter: parent.horizontalCenter
              columns: 3
              rowSpacing: Style.space(14)
              columnSpacing: Style.space(18)

              Repeater {
                model: 12

                MonthGrid {
                  required property int index
                  year: root.viewYear
                  month: index
                  weekStart: root.weekStart
                  todayKey: root.todayKey
                  eventDayKeys: root.eventDayKeys
                  journalDayKeys: root.journalDayKeys
                  compact: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onDayClicked: function(dateKeyValue) { root.openDay(dateKeyValue) }
                  onMonthLabelClicked: { root.viewMonth = index; root.setView("month") }
                }
              }
            }
          }
        }
      }

      // -------------------------------------------------------- Day detail --
      ColumnLayout {
        id: dayDetailPage
        anchors.fill: parent
        visible: root.dayDetailOpen
        spacing: Style.space(12)
        Keys.priority: Keys.AfterItem
        Keys.onEscapePressed: function(event) {
          root.closeDayDetail()
          event.accepted = true
        }

        Flickable {
          id: dayDetailFlick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: dayDetailInner.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          DayDetail {
            id: dayDetailInner
            width: dayDetailFlick.width
            dayDate: root.dayDetailDate
            dateKey: root.dayDetailKey
            events: root.dayEvents(root.dayDetailKey)
            service: root.service
            calendarOptions: root.calendarOptions
            embedded: false
            foreground: root.foreground
            accent: root.accent
            background: Color.popups.background
            fontFamily: root.fontFamily
            onCloseRequested: root.closeDayDetail()
            onOpenJournalEditorRequested: function(dateKeyValue) { root.openJournalEditor(dateKeyValue) }
          }
        }
      }
    }
  }
}
