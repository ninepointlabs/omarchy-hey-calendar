import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One day's content: its events (with inline add/edit/delete against the
// HEY CLI) and its journal entry (view, quick inline edit, or hand off to
// $EDITOR through a floating terminal). Used two ways by Panel.qml: embedded
// directly as the Today view's body, and as the content of the day-detail
// overlay opened by clicking a day in Week/Month/Year.
Item {
  id: root

  property var dayDate: new Date()
  property string dateKey: ""
  property var events: []
  property var service: null
  property var calendarOptions: []
  property bool embedded: false

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color background: Color.popups.background
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  signal closeRequested()
  signal openJournalEditorRequested(string dateKeyValue)

  readonly property var safeColorNames: ["black", "blue", "purple", "green", "red", "orange",
    "yellow", "pink", "brown", "teal", "indigo", "gray", "grey", "cyan", "magenta"]

  function eventDotColor(event) {
    var name = String(event && event.calendarColor || "").toLowerCase()
    return safeColorNames.indexOf(name) !== -1 ? name : root.accent
  }

  // ---- Add-event form
  property bool showAddForm: false
  property string addTitle: ""
  property bool addAllDay: false
  property string addStart: "09:00"
  property string addEnd: "10:00"
  property string addLocation: ""
  property string addCalendar: ""

  // Reads whatever was typed leniently ("9", "9:30am", "21:30", ...) rather
  // than requiring exact zero-padded 24h input — the strict form silently
  // left ADD disabled with no explanation for anything typed the way a
  // person actually types a time.
  readonly property bool addValid: addTitle.trim() !== ""
    && (addAllDay || (Model.normalizeTimeOfDay(addStart) !== "" && Model.normalizeTimeOfDay(addEnd) !== ""))
  readonly property bool addTimeUnreadable: !addAllDay
    && ((addStart.trim() !== "" && Model.normalizeTimeOfDay(addStart) === "") || (addEnd.trim() !== "" && Model.normalizeTimeOfDay(addEnd) === ""))

  function resetAddForm() {
    addTitle = ""
    addAllDay = false
    addStart = "09:00"
    addEnd = "10:00"
    addLocation = ""
    showAddForm = false
  }

  function submitAdd() {
    if (!addValid || !service) return
    var ok = service.addEvent({
      title: addTitle, date: dateKey, allDay: addAllDay,
      startTime: addAllDay ? "" : Model.normalizeTimeOfDay(addStart),
      endTime: addAllDay ? "" : Model.normalizeTimeOfDay(addEnd),
      location: addLocation, calendarId: addCalendar
    })
    if (ok) resetAddForm()
  }

  // ---- Inline event edit
  property string editingId: ""
  property string editTitle: ""
  property string editStart: ""
  property string editEnd: ""
  property string editLocation: ""

  readonly property bool editValid: editTitle.trim() !== ""
    && Model.normalizeTimeOfDay(editStart) !== "" && Model.normalizeTimeOfDay(editEnd) !== ""
  readonly property bool editTimeUnreadable: (editStart.trim() !== "" && Model.normalizeTimeOfDay(editStart) === "")
    || (editEnd.trim() !== "" && Model.normalizeTimeOfDay(editEnd) === "")

  function startEdit(event) {
    editingId = event.id
    editTitle = event.title
    editLocation = event.location
    var start = new Date(event.startsAt)
    var end = new Date(event.endsAt || event.startsAt)
    editStart = isNaN(start.getTime()) ? "09:00" : pad2(start.getHours()) + ":" + pad2(start.getMinutes())
    editEnd = isNaN(end.getTime()) ? "10:00" : pad2(end.getHours()) + ":" + pad2(end.getMinutes())
  }

  function pad2(n) { return (n < 10 ? "0" : "") + n }

  function cancelEdit() { editingId = "" }

  function submitEdit() {
    if (!editValid || !service) return
    var ok = service.editEvent(editingId, {
      title: editTitle, startTime: Model.normalizeTimeOfDay(editStart), endTime: Model.normalizeTimeOfDay(editEnd),
      location: editLocation
    })
    if (ok) editingId = ""
  }

  property string confirmDeleteEventId: ""
  function requestDeleteEvent(id) { confirmDeleteEventId = id }

  function confirmDeleteEventNow() {
    if (service) service.deleteEvent(confirmDeleteEventId)
    confirmDeleteEventId = ""
  }

  // ---- Journal
  property bool journalEditing: false
  property string journalDraft: ""
  property bool confirmDeleteJournal: false

  function startJournalEdit() {
    journalDraft = service ? service.journalContent : ""
    journalEditing = true
  }

  function cancelJournalEdit() { journalEditing = false }

  function submitJournal() {
    if (!service) return
    if (service.writeJournal(dateKey, journalDraft)) journalEditing = false
  }

  function requestDeleteJournal() { confirmDeleteJournal = true }

  function confirmDeleteJournalNow() {
    if (service) service.writeJournal(dateKey, "")
    confirmDeleteJournal = false
    journalEditing = false
  }

  width: parent ? parent.width : 400
  implicitHeight: innerColumn.implicitHeight
  height: implicitHeight

  Column {
    id: innerColumn
    width: parent.width
    spacing: Style.space(14)

    // ---- Header
    Item {
      width: parent.width
      height: Math.max(headerText.implicitHeight, closeButton.implicitHeight)

    Text {
      id: headerText
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: root.embedded ? parent.right : closeButton.left
      anchors.rightMargin: root.embedded ? 0 : Style.space(8)
      text: Qt.formatDate(root.dayDate, "dddd, MMMM d")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      elide: Text.ElideRight
    }

    PanelActionButton {
      id: closeButton
      visible: !root.embedded
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅖"
      tooltipText: "Close"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.closeRequested()
    }
  }

  PanelSeparator { foreground: root.foreground }

  // ---- Events
  Column {
    width: parent.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: "EVENTS"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }

    Text {
      visible: root.events.length === 0 && !root.showAddForm
      text: "Nothing on the calendar."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Repeater {
      model: root.events

      Column {
        id: eventRow
        required property var modelData
        width: parent.width
        spacing: Style.space(4)

        Item {
          width: parent.width
          height: Math.max(eventMainRow.implicitHeight, Style.space(22))
          visible: root.editingId !== eventRow.modelData.id

          Row {
            id: eventMainRow
            anchors.left: parent.left
            anchors.right: eventActions.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(8)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(7); height: Style.space(7); radius: width / 2
              color: root.eventDotColor(eventRow.modelData)
            }

            Column {
              width: parent.width - Style.space(15)
              spacing: Style.space(1)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: eventRow.modelData.title
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: [Model.eventTimeRangeLabel(eventRow.modelData), eventRow.modelData.location].filter(function(s) { return s !== "" }).join(" · ")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }

          Row {
            id: eventActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelActionButton {
              iconText: "✎"
              tooltipText: "Edit"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.startEdit(eventRow.modelData)
            }

            PanelActionButton {
              iconText: "󰅖"
              tooltipText: "Delete"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.requestDeleteEvent(eventRow.modelData.id)
            }
          }
        }

        // ---- Inline edit form
        Column {
          visible: root.editingId === eventRow.modelData.id
          width: parent.width
          spacing: Style.space(6)
          topPadding: Style.space(2)
          bottomPadding: Style.space(6)

          TextField {
            width: parent.width
            placeholderText: "Title"
            foreground: root.foreground
            accent: root.accent
            onTextChanged: root.editTitle = text
            Binding on text { value: root.editTitle }
          }

          Row {
            spacing: Style.space(8)

            TextField {
              width: Style.space(90)
              placeholderText: "09:00"
              foreground: root.foreground
              accent: root.accent
              onTextChanged: root.editStart = text
              Binding on text { value: root.editStart }
            }

            Text { anchors.verticalCenter: parent.verticalCenter; text: "–"; color: root.dim; font.family: root.fontFamily }

            TextField {
              width: Style.space(90)
              placeholderText: "10:00"
              foreground: root.foreground
              accent: root.accent
              onTextChanged: root.editEnd = text
              Binding on text { value: root.editEnd }
            }
          }

          Text {
            visible: root.editTimeUnreadable
            width: parent.width
            text: "Times like 9:00, 9:30am, or 21:30 all work — that one isn't readable."
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          TextField {
            width: parent.width
            placeholderText: "Location (optional)"
            foreground: root.foreground
            accent: root.accent
            onTextChanged: root.editLocation = text
            Binding on text { value: root.editLocation }
          }

          Row {
            spacing: Style.space(8)

            Button {
              text: "SAVE"
              bordered: true
              enabled: root.editValid && !(root.service && root.service.mutating)
              foreground: root.foreground
              background: root.background
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(4)
              onClicked: root.submitEdit()
            }

            Button {
              text: "CANCEL"
              foreground: root.dim
              background: "transparent"
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(4)
              onClicked: root.cancelEdit()
            }
          }
        }
      }
    }

    // ---- Add event
    Column {
      width: parent.width
      spacing: Style.space(6)
      topPadding: Style.space(4)

      Button {
        visible: !root.showAddForm
        text: "+ ADD EVENT"
        foreground: root.dim
        background: "transparent"
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(4)
        verticalPadding: Style.space(2)
        onClicked: root.showAddForm = true
      }

      Column {
        visible: root.showAddForm
        width: parent.width
        spacing: Style.space(6)

        TextField {
          width: parent.width
          placeholderText: "New event title"
          foreground: root.foreground
          accent: root.accent
          onTextChanged: root.addTitle = text
          Binding on text { value: root.addTitle }
        }

        Toggle {
          width: parent.width
          label: "All day"
          checked: root.addAllDay
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onClicked: root.addAllDay = !root.addAllDay
        }

        Row {
          visible: !root.addAllDay
          spacing: Style.space(8)

          TextField {
            width: Style.space(90)
            placeholderText: "09:00"
            foreground: root.foreground
            accent: root.accent
            onTextChanged: root.addStart = text
            Binding on text { value: root.addStart }
          }

          Text { anchors.verticalCenter: parent.verticalCenter; text: "–"; color: root.dim; font.family: root.fontFamily }

          TextField {
            width: Style.space(90)
            placeholderText: "10:00"
            foreground: root.foreground
            accent: root.accent
            onTextChanged: root.addEnd = text
            Binding on text { value: root.addEnd }
          }
        }

        Text {
          visible: root.addTimeUnreadable
          width: parent.width
          text: "Times like 9:00, 9:30am, or 21:30 all work — that one isn't readable."
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        TextField {
          width: parent.width
          placeholderText: "Location (optional)"
          foreground: root.foreground
          accent: root.accent
          onTextChanged: root.addLocation = text
          Binding on text { value: root.addLocation }
        }

        Dropdown {
          visible: root.calendarOptions.length > 1
          width: parent.width
          showLabel: false
          options: root.calendarOptions
          foreground: root.foreground
          background: root.background
          accent: root.accent
          fontFamily: root.fontFamily
          onChanged: function(value) { root.addCalendar = value }
          Binding on value { value: root.addCalendar }
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "ADD"
            bordered: true
            enabled: root.addValid && !(root.service && root.service.mutating)
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(4)
            onClicked: root.submitAdd()
          }

          Button {
            text: "CANCEL"
            foreground: root.dim
            background: "transparent"
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(4)
            onClicked: root.resetAddForm()
          }
        }
      }
    }
  }

  PanelSeparator { foreground: root.foreground }

  // ---- Journal
  Column {
    width: parent.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: "JOURNAL"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }

    Text {
      visible: root.service && root.service.journalLoading
      text: "Loading…"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Column {
      visible: !root.journalEditing && !(root.service && root.service.journalLoading)
      width: parent.width
      spacing: Style.space(8)

      Text {
        width: parent.width
        visible: root.service && root.service.journalExists
        text: root.service ? root.service.journalContent : ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        visible: !(root.service && root.service.journalExists)
        text: "No journal entry for this day."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Row {
        spacing: Style.space(8)

        Button {
          text: root.service && root.service.journalExists ? "EDIT" : "+ WRITE ENTRY"
          foreground: root.dim
          background: "transparent"
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(4)
          verticalPadding: Style.space(2)
          onClicked: root.startJournalEdit()
        }

        Button {
          text: "OPEN IN EDITOR"
          foreground: root.dim
          background: "transparent"
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(4)
          verticalPadding: Style.space(2)
          onClicked: root.openJournalEditorRequested(root.dateKey)
        }

        Button {
          visible: root.service && root.service.journalExists
          text: "DELETE"
          foreground: root.dim
          background: "transparent"
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(4)
          verticalPadding: Style.space(2)
          onClicked: root.requestDeleteJournal()
        }
      }
    }

    Column {
      visible: root.journalEditing
      width: parent.width
      spacing: Style.space(6)

      TextArea {
        id: journalArea
        width: parent.width
        height: Style.space(120)
        wrapMode: TextArea.Wrap
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        selectByMouse: true
        background: Rectangle {
          color: root.background
          radius: Style.cornerRadius
          border.width: Style.spacing.hairline
          border.color: Qt.darker(root.foreground, 2.2)
        }
        onTextChanged: root.journalDraft = text
        Binding on text { value: root.journalDraft }
      }

      Row {
        spacing: Style.space(8)

        Button {
          text: "SAVE"
          bordered: true
          enabled: !(root.service && root.service.mutating)
          foreground: root.foreground
          background: root.background
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(10)
          verticalPadding: Style.space(4)
          onClicked: root.submitJournal()
        }

        Button {
          text: "CANCEL"
          foreground: root.dim
          background: "transparent"
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(10)
          verticalPadding: Style.space(4)
          onClicked: root.cancelJournalEdit()
        }
      }
    }
  }
  } // innerColumn

  ConfirmDialog {
    anchors.fill: parent
    opened: root.confirmDeleteEventId !== ""
    message: "Delete this event?"
    confirmText: "Delete"
    background: root.background
    foreground: root.foreground
    fontFamily: root.fontFamily
    onCanceled: root.confirmDeleteEventId = ""
    onConfirmed: root.confirmDeleteEventNow()
  }

  ConfirmDialog {
    anchors.fill: parent
    opened: root.confirmDeleteJournal
    message: "Delete this journal entry?"
    confirmText: "Delete"
    background: root.background
    foreground: root.foreground
    fontFamily: root.fontFamily
    onCanceled: root.confirmDeleteJournal = false
    onConfirmed: root.confirmDeleteJournalNow()
  }
}
