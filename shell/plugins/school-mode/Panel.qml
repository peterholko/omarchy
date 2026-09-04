import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ModeState.js" as ModeState

// The mode pill's panel: which mode, why, the school apps, and the switch.
// School mode is the kid's to start any time; leaving it inside school hours
// is the parent's, so the daemon answers parent_required and the panel asks
// for the parent password, which goes to the daemon over stdin.
Panel {
  id: root
  moduleName: "omarchy.school-mode.mode"
  ipcTarget: "omarchy.school-mode.mode"

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property string note: ""
  property bool noteIsError: false
  property bool askingParent: false
  property string pendingMode: ""

  readonly property var barIdentity: hostWidget || root
  readonly property bool schoolMode: service ? service.schoolMode === true : false
  readonly property string reasonLine: service ? ModeState.reasonLine({
    enabled: service.timeEnabled, mode: service.mode, reason: service.modeReason,
    schoolUntil: service.schoolUntil, schoolLabel: service.schoolLabel }) : ""
  readonly property int schoolAppCount: service && service.allowedDesktopIds ? service.allowedDesktopIds.length : 0
  readonly property string clientPath: Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-parent-time-client"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property color errorColor: Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.note = ""
    root.noteIsError = false
    root.askingParent = false
    passwordField.text = ""
    root.controller.show()
  }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function closeForPopoutSwitch() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // The switch: school mode any time, free time with the password when the
  // daemon says the parent must; the daemon decides, the panel only asks.
  function requestMode(mode, password) {
    if (modeProc.running) return
    root.pendingMode = mode
    modeProc.pendingPassword = String(password || "")
    modeProc.launched = false
    modeProc.command = [root.clientPath, "--password-stdin", "mode", mode]
    modeProc.running = true
  }

  function switchMode() {
    requestMode(root.schoolMode ? "free" : "school", "")
  }

  function submitParent() {
    var password = passwordField.text
    if (password.trim() === "") return
    requestMode(root.pendingMode || "free", password)
  }

  function handleModeReply(rawText) {
    var payload
    try { payload = JSON.parse(rawText) } catch (e) { payload = null }
    passwordField.text = ""
    if (payload && payload.ok === true) {
      root.askingParent = false
      root.note = payload.mode === "school" ? "School mode is on." : "Free time."
      root.noteIsError = false
      return
    }
    var error = payload ? String(payload.error || "") : ""
    if (error === "parent_required") {
      root.askingParent = true
      root.note = "It is " + String(payload.label || "school").toLowerCase() + " until " + String(payload.until || "") + ". A parent can take free time."
      root.noteIsError = false
      Qt.callLater(function() { passwordField.forceActiveFocus() })
      return
    }
    root.noteIsError = true
    if (error === "bad_password") root.note = "That is not the parent password."
    else if (error === "password_locked_out") root.note = "Too many tries. Wait " + payload.retry_in_seconds + " s."
    else root.note = "Could not switch: " + (error || "no answer from screen time")
  }

  Process {
    id: modeProc
    property string pendingPassword: ""
    property bool launched: false
    stdinEnabled: true
    onStarted: { launched = true; write(pendingPassword + "\n") }
    stdout: StdioCollector { id: modeOut; waitForEnd: true }
    onExited: root.handleModeReply(modeOut.text)
    // A client that could not start at all comes as runningChanged alone,
    // no exited; the panel must not wait on it forever.
    onRunningChanged: if (!running && !launched) root.handleModeReply("")
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: root.askingParent ? passwordField : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(420))

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.switchMode(); event.accepted = true }
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          foreground: root.foreground
          title: root.schoolMode ? "School mode" : "Free time"
          detail: root.schoolMode ? root.schoolAppCount + " apps" : "everything"
          meta: root.reasonLine
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.schoolMode ? "\uf02d" : "\uf185"
              color: root.schoolMode ? root.accent : root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.schoolMode
            ? "The menu shows the school apps, their shortcuts alone work, notifications are quiet, and the browser is the school one. Free-time windows are parked and come back after."
            : "The whole launcher, notifications, and the browser with your account. School hours switch to school mode on their own."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Button {
          width: parent.width
          text: root.schoolMode ? "Back to free time" : "Start school mode"
          bordered: true
          selected: !root.schoolMode
          focusable: true
          enabled: !modeProc.running && root.service && root.service.timeEnabled === true
          onClicked: root.switchMode()
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.askingParent

          TextField {
            id: passwordField
            width: parent.width
            password: true
            placeholderText: "Parent password"
            activeFocusOnTab: true
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.submitParent(); event.accepted = true }
              else if (event.key === Qt.Key_Escape) { root.askingParent = false; event.accepted = true }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.note !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.note
          color: root.noteIsError ? root.errorColor : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}
