import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "MathModel.js" as Quiz

// Math time (plans/kids-screen-time.md): the session where screen time is
// earned. Full screen and holding the keyboard, like the lock screen, so it
// is the only thing on screen; root's guard locks the session if it leaves
// while the budget is empty. Questions come from and answers go to
// omarchy-parent-quiz through the kid's passwordless sudo grant, so root
// keeps the answers and the credits. Opened by the lock screen after an
// unlock with no time left, and from the menu any time, to earn ahead.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string statusPath: "/var/lib/omarchy/parent/" + userName + "/time/status.json"
  property string statusRaw: ""
  readonly property var status: Quiz.gateFromStatus(statusRaw, true)

  // One session.
  property int answered: 0
  property int right: 0
  property int earned: 0
  property string questionId: ""
  property string questionText: ""
  property string feedback: ""
  property bool checking: false
  property bool finished: false
  property double startedAt: 0
  property int elapsedSeconds: 0
  property string answerText: ""

  readonly property int total: Math.max(1, status.questions)
  readonly property string progress: Quiz.progressLabel(answered, total)
  readonly property string promise: total + (total === 1 ? " question earns " : " questions earn ") + status.sessionMinutes + " minutes"
  readonly property string balance: Quiz.remainingLabel(status.budget)
  readonly property string results: Quiz.resultsSummary(right, total, elapsedSeconds, earned, status.budget)

  function open(payloadJson) {
    statusView.reload()
    startSession()
    opened = true
  }

  function close() {
    opened = false
    questionId = ""
    questionText = ""
    feedback = ""
    answerText = ""
  }

  function toggle() {
    if (opened) close()
    else open("{}")
  }

  function startSession() {
    answered = 0
    right = 0
    earned = 0
    finished = false
    feedback = ""
    answerText = ""
    startedAt = Date.now()
    elapsedSeconds = 0
    askQuestion()
  }

  function askQuestion() {
    if (questionProc.running) return
    feedback = ""
    answerText = ""
    questionProc.running = true
  }

  function submit() {
    if (finished) {
      // Done: leave, or go again when there is still no time.
      if (status.budget <= 0 && status.enabled) startSession()
      else close()
      return
    }
    var answer = Quiz.normalizeAnswer(answerText)
    if (checking || answerProc.running) return
    if (questionId.length === 0) { askQuestion(); return }
    if (answer.length === 0) return
    checking = true
    answerProc.command = ["bash", "-c", "printf '%s %s\\n' " + Util.shellQuote(questionId) + " " + Util.shellQuote(answer) + " | sudo -n /usr/bin/omarchy-parent-quiz answer"]
    answerProc.running = true
  }

  function handleAnswer(reply) {
    checking = false
    var result = Quiz.parseAnswer(reply)
    feedback = Quiz.feedback(result)
    statusView.reload()
    if (result.kind === "correct") {
      right += 1
      earned += result.credited
    }
    if (Quiz.questionDone(result)) {
      answered += 1
      questionId = ""
      if (answered >= total) {
        finished = true
        elapsedSeconds = Math.floor((Date.now() - startedAt) / 1000)
        return
      }
    }
    // A wrong first try keeps the question; anything else brings the next.
    if (result.kind !== "wrong" || result.expected) nextQuestionTimer.restart()
    else answerText = ""
  }

  Timer {
    id: nextQuestionTimer
    interval: 1200
    onTriggered: root.askQuestion()
  }

  Timer {
    interval: 1000
    running: root.opened && !root.finished
    repeat: true
    onTriggered: root.elapsedSeconds = Math.floor((Date.now() - root.startedAt) / 1000)
  }

  // status.json is root's and world-readable; every credit rewrites it.
  FileView {
    id: statusView
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onLoaded: root.statusRaw = text()
    onLoadFailed: root.statusRaw = ""
    onFileChanged: reload()
  }

  Process {
    id: questionProc
    command: ["sudo", "-n", "/usr/bin/omarchy-parent-quiz", "question"]
    stdout: StdioCollector { id: questionOut; waitForEnd: true }
    onExited: function(exitCode) {
      var question = Quiz.parseQuestion(questionOut.text)
      if (exitCode === 0 && question) {
        root.questionId = question.id
        root.questionText = question.text
      } else {
        root.questionId = ""
        root.questionText = ""
        root.feedback = "Could not get a question. Press Enter to try again."
      }
    }
  }

  Process {
    id: answerProc
    stdout: StdioCollector { id: answerOut; waitForEnd: true }
    onExited: root.handleAnswer(answerOut.text)
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: Color.lock.background
    WlrLayershell.namespace: "omarchy-math"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // The screen stays on while she works, on paper or otherwise.
    IdleInhibitor {
      window: panel
      enabled: root.opened
    }

    Column {
      anchors.centerIn: parent
      width: Math.min(parent.width - 96, 900)
      spacing: Style.spacing.lg

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "Math time"
        color: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.heading * 1.25)
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        objectName: "promise"
        textFormat: Text.PlainText
        width: parent.width
        text: root.finished ? "Session done" : root.promise + "  ·  " + root.progress
        color: Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        objectName: "question"
        textFormat: Text.PlainText
        width: parent.width
        visible: !root.finished
        text: root.questionText.length > 0 ? root.questionText : "…"
        color: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.heading * 2)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Text {
        objectName: "results"
        textFormat: Text.PlainText
        width: parent.width
        visible: root.finished
        text: root.results + (root.status.budget <= 0 ? "  Press Enter for another session." : "  Press Enter to go.")
        color: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.heading * 1.25)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      BorderSurface {
        id: field
        visible: !root.finished
        width: 381
        height: 67
        anchors.horizontalCenter: parent.horizontalCenter
        color: Color.lock.background
        borderSpec: Border.surfaceSpec("lock", "border-active", Color.lock.borderActive, 3, "border-alpha")
        radius: Style.cornerRadius

        RegularExpressionValidator {
          id: digitsOnly
          regularExpression: /[0-9]{0,9}/
        }

        TextInput {
          id: answerInput
          anchors.fill: parent
          anchors.leftMargin: 18
          anchors.rightMargin: 18
          verticalAlignment: TextInput.AlignVCenter
          horizontalAlignment: TextInput.AlignHCenter
          focus: root.opened && !root.finished
          enabled: !root.checking
          readOnly: root.checking
          inputMethodHints: Qt.ImhDigitsOnly
          validator: digitsOnly
          text: root.answerText
          color: Color.lock.text
          selectionColor: Color.lock.selection
          selectedTextColor: Color.lock.text
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.heading * 1.125)
          onTextChanged: root.answerText = text
          onAccepted: root.submit()
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
            else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U) { root.answerText = ""; event.accepted = true }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.fill: answerInput
          visible: answerInput.text.length === 0
          text: root.checking ? "Checking…" : (root.feedback.length > 0 ? root.feedback : "Your answer")
          color: root.feedback.length > 0 ? Color.lock.text : Color.lock.placeholder
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.heading * 1.125)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }
      }

      // Enter on the results screen: the field is gone, so catch it here.
      Item {
        visible: root.finished
        focus: root.opened && root.finished
        width: 1; height: 1
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.submit(); event.accepted = true }
          else if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
        }
      }

      Text {
        objectName: "balance"
        textFormat: Text.PlainText
        width: parent.width
        text: root.balance + (root.finished ? "" : "  ·  " + Quiz.formatDuration(root.elapsedSeconds) + "  ·  Enter to answer, Esc to leave")
        color: Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
