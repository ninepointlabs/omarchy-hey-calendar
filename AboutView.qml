import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "About.js" as About

// The panel's About page: who made HEY Calendar, its version and license,
// where to get help, and what it does with your data. Panel.qml swaps it in
// for the calendar (info button, `i`, or the `about` IPC call). It takes the
// panel as its one input (`host`) for theme colors and the shared service;
// see the README's note on this Quickshell build and outside assignments.
Column {
  id: root

  property var host: null

  readonly property color foreground: host ? host.foreground : Color.foreground
  readonly property color accent: host ? host.accent : Color.accent
  readonly property string fontFamily: host ? host.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  property bool loaded: false
  property bool showLicense: false
  property bool showNotices: false
  property string notice: ""

  signal backRequested()

  // This plugin's own folder, wherever it is installed.
  readonly property string pluginDir: {
    var text = String(Qt.resolvedUrl("."))
    if (text.indexOf("file://") === 0) text = decodeURIComponent(text.substring(7))
    return text.length > 1 && text.charAt(text.length - 1) === "/" ? text.substring(0, text.length - 1) : text
  }

  readonly property string version: About.manifestVersion(manifestFile.loaded ? manifestFile.text() : "")
  readonly property var versions: ({
    quickshell: About.probedVersion(function(a, b) { return Quickshell.hasVersion(a, b) }, 0),
    qt: About.probedVersion(function(a, b) { return Quickshell.hasQtVersion(a, b) }, 6),
    hey: host && host.service ? host.service.cliVersion : ""
  })
  readonly property string details: About.details(root.version, root.versions,
    (Quickshell.env("XDG_CURRENT_DESKTOP") || "unknown desktop") + ", " + Qt.platform.pluginName)
  readonly property real labelWidth: Style.space(72)

  function copy(text, what) {
    Quickshell.clipboardText = text
    root.notice = what + " copied"
    noticeTimer.restart()
  }

  spacing: Style.space(12)
  onVisibleChanged: {
    if (visible) root.loaded = true
    else { root.showLicense = false; root.showNotices = false; root.notice = "" }
  }

  // Read only once the page has been shown.
  FileView { id: manifestFile; path: root.loaded ? root.pluginDir + "/manifest.json" : ""; printErrors: false }
  FileView { id: licenseFile; path: root.loaded ? root.pluginDir + "/LICENSE" : ""; printErrors: false }
  FileView { id: noticesFile; path: root.showNotices ? root.pluginDir + "/THIRD_PARTY_NOTICES.md" : ""; printErrors: false }

  Timer { id: noticeTimer; interval: 2500; onTriggered: root.notice = "" }

  Item {
    width: parent.width
    height: backButton.implicitHeight

    Button {
      id: backButton
      objectName: "aboutBack"
      iconText: "󰁍"
      text: "Back"
      tooltipText: "Back to the calendar (Esc)"
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: root.backRequested()
    }
  }

  Row {
    width: parent.width
    spacing: Style.space(14)

    Text {
      id: appIcon
      text: "󰃭"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.display * 1.5
      anchors.verticalCenter: parent.verticalCenter
    }

    Column {
      width: parent.width - appIcon.width - parent.spacing
      spacing: Style.space(3)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        text: About.NAME
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: About.TAGLINE
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        objectName: "aboutVersion"
        text: "Version " + (root.version || "unknown")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  PanelSeparator { foreground: root.foreground }

  Grid {
    width: parent.width
    columns: 2
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(8)
    verticalItemAlignment: Grid.AlignVCenter

    Text { width: root.labelWidth; text: "Made by"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    Text { text: About.ORGANIZATION; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }

    Text { width: root.labelWidth; text: "Created"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    Text { text: About.CREATED; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }

    Text { width: root.labelWidth; text: "License"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    Row {
      spacing: Style.space(6)
      Text {
        objectName: "aboutLicenseSummary"
        anchors.verticalCenter: parent.verticalCenter
        text: About.licenseSummary(licenseFile.loaded ? licenseFile.text() : "") || "MIT License"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Button {
        objectName: "aboutLicense"
        text: root.showLicense ? "Hide" : "Read it"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        onClicked: root.showLicense = !root.showLicense
      }
      Button {
        objectName: "aboutNotices"
        text: root.showNotices ? "Hide notices" : "Third-party notices"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        onClicked: root.showNotices = !root.showNotices
      }
    }

    Text { width: root.labelWidth; text: "Support"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    Row {
      spacing: Style.space(6)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: About.SUPPORT_EMAIL
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Button {
        text: "Email"
        tooltipText: "Opens your mail app with the version details filled in"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        onClicked: Qt.openUrlExternally(About.mailto(root.version, root.details))
      }
      Button {
        text: "Copy"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        onClicked: root.copy(About.SUPPORT_EMAIL, "Address")
      }
    }
  }

  Text {
    width: parent.width
    text: "PRIVACY"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }
  Text {
    objectName: "aboutPrivacy"
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: About.PRIVACY
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    objectName: "aboutBuiltWith"
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Built with " + About.builtWith(root.versions)
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    objectName: "aboutLicenseText"
    visible: root.showLicense
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: licenseFile.loaded ? About.reflow(licenseFile.text()) : "LICENSE could not be read from the plugin folder."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    objectName: "aboutNoticesText"
    visible: root.showNotices
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: noticesFile.loaded ? About.reflow(noticesFile.text()) : "See THIRD_PARTY_NOTICES.md in the plugin folder."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Row {
    width: parent.width
    spacing: Style.space(8)
    layoutDirection: Qt.RightToLeft

    Button {
      objectName: "aboutCopyDetails"
      text: "Copy version details"
      bordered: true
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: root.copy(root.details, "Version details")
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.notice
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
