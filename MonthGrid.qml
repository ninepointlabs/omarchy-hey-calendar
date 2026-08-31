import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A month grid — always six rows so the block never resizes between months,
// the same contract omarchy.clock's popup uses. Doubles as the Year view's
// twelve mini-months via `compact`, which drops the week-number gutter and
// shrinks the cells; both modes draw an activity pip under any day that has
// an event or a journal entry.
Column {
  id: root

  property int year: (new Date()).getFullYear()
  property int month: (new Date()).getMonth()
  property int weekStart: 1
  property string todayKey: ""
  property var eventDayKeys: ({})   // dateKey -> true (has at least one event)
  property var journalDayKeys: ({}) // dateKey -> true (has a journal entry)
  property bool compact: false

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal dayClicked(string dateKey)
  signal monthLabelClicked()

  readonly property var weeks: Model.monthGrid(year, month, weekStart, todayKey)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var labelLocale: Qt.locale("en_US")

  readonly property int cellSize: compact ? Style.space(20) : Style.space(52)
  readonly property int cellHeight: compact ? Style.space(18) : Style.space(44)
  readonly property int cellSpacing: compact ? 1 : Style.space(2)
  readonly property int weekColumnWidth: compact ? 0 : Style.space(28)
  readonly property int gutterWidth: compact ? 0 : Style.space(10)

  spacing: Style.space(3)

  Item {
    visible: !root.compact
    width: parent.width
    height: monthLabelMouse.height

    Text {
      id: monthLabel
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDate(new Date(root.year, root.month, 1), "MMMM yyyy").toUpperCase()
      color: Qt.darker(root.foreground, 1.3)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.letterSpacing: 1
      font.bold: true
    }

    MouseArea {
      id: monthLabelMouse
      anchors.centerIn: monthLabel
      width: monthLabel.implicitWidth + Style.space(12)
      height: monthLabel.implicitHeight + Style.space(8)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.monthLabelClicked()
    }
  }

  Text {
    visible: root.compact
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    text: Model.monthName(root.month).toUpperCase()
    color: Qt.darker(root.foreground, 1.2)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
    font.bold: true

    MouseArea {
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      cursorShape: Qt.PointingHandCursor
      onClicked: root.monthLabelClicked()
    }
  }

  Row {
    visible: !root.compact
    spacing: root.cellSpacing

    Item { width: root.weekColumnWidth; height: Style.space(14) }
    Item { width: root.gutterWidth; height: Style.space(14) }

    Repeater {
      model: root.weekdays

      Text {
        textFormat: Text.PlainText
        required property var modelData
        width: root.cellSize
        height: Style.space(14)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.labelLocale.dayName(modelData, Locale.ShortFormat).substring(0, 2).toUpperCase()
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  Repeater {
    model: root.weeks

    Row {
      required property var modelData
      spacing: root.cellSpacing

      Text {
        visible: !root.compact
        textFormat: Text.PlainText
        width: root.weekColumnWidth
        height: root.cellHeight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: modelData.week
        color: Qt.darker(root.foreground, 1.9)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Item { visible: !root.compact; width: root.gutterWidth; height: root.cellHeight }

      Repeater {
        model: modelData.days

        Rectangle {
          id: cell
          required property var modelData
          readonly property bool hasEvent: root.eventDayKeys[modelData.key] === true
          readonly property bool hasJournal: root.journalDayKeys[modelData.key] === true

          width: root.cellSize
          height: root.cellHeight
          radius: Style.cornerRadius
          color: dayMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
          border.width: modelData.today ? Style.spacing.hairline : 0
          border.color: Style.normalBorderFor(root.foreground, root.accent)

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            anchors.verticalCenterOffset: cell.hasEvent || cell.hasJournal ? -Style.space(3) : 0
            text: cell.modelData.day
            color: cell.modelData.inMonth
              ? (cell.modelData.weekend ? Qt.darker(root.foreground, 1.45) : root.foreground)
              : Qt.darker(root.foreground, 2.2)
            font.family: root.fontFamily
            font.pixelSize: root.compact ? Style.font.caption : Style.font.body
            font.bold: cell.modelData.today
          }

          Row {
            visible: !root.compact && (cell.hasEvent || cell.hasJournal)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(5)
            spacing: Style.space(3)

            Rectangle {
              visible: cell.hasEvent
              width: Style.space(4); height: Style.space(4); radius: width / 2
              color: root.accent
            }
            Rectangle {
              visible: cell.hasJournal
              width: Style.space(4); height: Style.space(4); radius: width / 2
              color: Qt.darker(root.foreground, 1.4)
            }
          }

          Rectangle {
            visible: root.compact && (cell.hasEvent || cell.hasJournal)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(1)
            width: Style.space(3); height: Style.space(3); radius: width / 2
            color: cell.hasEvent ? root.accent : Qt.darker(root.foreground, 1.4)
          }

          MouseArea {
            id: dayMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dayClicked(cell.modelData.key)
          }
        }
      }
    }
  }
}
