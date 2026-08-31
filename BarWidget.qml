import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The bar chip: today's date, or the next upcoming event when one exists and
// the setting allows it — then hosts the full Today/Week/Month/Year panel on
// click, the same Loader + hostWidget handoff omarchy.clock uses so this
// widget can stand in for the panel as the bar's popout identity.
BarWidget {
  id: root
  moduleName: "tim.hey-calendar"

  property date today: clock.date
  readonly property string todayKey: Model.keyForDate(today)

  readonly property bool showNextEvent: setting("showNextEvent", true) === true

  readonly property var service: panelLoader.item ? panelLoader.item.service : null
  readonly property var todaysEvents: service ? Model.eventsOnDay(service.windowEvents, todayKey) : []
  readonly property string nextEvent: showNextEvent && service ? Model.nextEventLabel(todaysEvents, Date.now()) : ""

  readonly property string dateText: Qt.formatDate(today, "ddd d MMM")
  readonly property string displayText: nextEvent !== "" ? nextEvent : dateText
  readonly property var verticalLines: [Qt.formatDate(today, "ddd"), Qt.formatDate(today, "d")]

  function refresh() {
    today = new Date()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  // ---- Panel popup. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.today = date
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "tim.hey-calendar"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    // Called back by the floating terminal's `hey journal write` handoff
    // once $EDITOR closes, so the open day's entry refreshes immediately.
    function journalEditFinished(): string {
      if (root.service) root.service.fetchJournalEntry(root.service.openDayKey)
      return "ok"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.nextEvent !== "" ? "HEY Calendar · " + root.nextEvent : "HEY Calendar"

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
