// KOX OS lockscreen — TEST WINDOW (window-mode, no session lock).
// Same UI and the same PAM wiring as the real lock.qml will use, but drawn
// in a plain frameless window so the look and the PamContext can be
// verified safely before touching WlSessionLock. Run:
//   quickshell -p ~/.config/quickshell/test.qml
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Services.Pam

Scope {
    id: root

    signal unlocked()
    signal failed()

    // Shared auth state (the real lock keeps this in a context too, so all
    // monitor surfaces render the same text/failure state).
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property bool showSuccess: false
    property real failFlash: 0

    onCurrentTextChanged: showFailure = false

    function tryUnlock() {
        if (currentText === "" || unlockInProgress)
            return
        unlockInProgress = true
        showSuccess = false
        pam.start()
    }

    PamContext {
        id: pam
        configDirectory: "pam"
        config: "lock.conf"
        // pam_unix asks for the password as an echo-off prompt.
        onPamMessage: {
            if (this.responseRequired)
                this.respond(root.currentText)
        }
        onCompleted: result => {
            root.unlockInProgress = false
            if (result == PamResult.Success) {
                root.unlocked()
            } else {
                root.currentText = ""
                root.failed()
            }
        }
    }

    onUnlocked: {
        showSuccess = true
        console.log("KOX-LOCK: PAM SUCCESS - would unlock the session")
        successHide.restart()
    }
    onFailed: {
        showFailure = true
        console.log("KOX-LOCK: PAM failed - clearing entry")
        failFx.restart()
    }

    ParallelAnimation {
        id: failFx
        // red flash on the pill border
        SequentialAnimation {
            NumberAnimation { target: root; property: "failFlash"; to: 1; duration: 70 }
            NumberAnimation { target: root; property: "failFlash"; to: 0; duration: 550; easing.type: Easing.OutCubic }
        }
        // horizontal shake
        SequentialAnimation {
            NumberAnimation { target: shake; property: "x"; to: -9; duration: 45 }
            NumberAnimation { target: shake; property: "x"; to: 9; duration: 45 }
            NumberAnimation { target: shake; property: "x"; to: -6; duration: 45 }
            NumberAnimation { target: shake; property: "x"; to: 6; duration: 45 }
            NumberAnimation { target: shake; property: "x"; to: 0; duration: 45 }
        }
    }

    Timer {
        id: successHide
        interval: 2600
        onTriggered: root.showSuccess = false
    }

    Window {
        id: win
        visible: true
        title: "KOX lock test"
        width: 480
        height: 700
        color: "transparent"
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint

        Rectangle {
            anchors.fill: parent
            color: "#101218"
            radius: 20
            border.color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            focus: true
            Keys.onEscapePressed: Qt.quit()

            Column {
                anchors.centerIn: parent
                spacing: 24

                // ── clock: big thin hours, smaller minutes, one baseline ──
                Text {
                    id: clock
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.RichText
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.ExtraLight
                    property var now: new Date()
                    text: "<span style=\"font-size:76px; color:#f8f8f2\">"
                          + Qt.formatDateTime(now, "HH")
                          + "</span><span style=\"font-size:44px; color:rgba(248,248,242,0.55)\">"
                          + Qt.formatDateTime(now, ":mm") + "</span>"
                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        onTriggered: clock.now = new Date()
                    }
                }

                // ── date line ──
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.letterSpacing: 3
                    color: "#8f959e"
                    text: Qt.formatDateTime(clock.now, "dddd · MMMM d").toString().toUpperCase()
                }

                // ── password pill ──
                Item {
                    id: pillWrap
                    width: pillRow.width + 44
                    height: 54
                    anchors.horizontalCenter: parent.horizontalCenter
                    transform: Translate { id: shake }

                    Rectangle {
                        anchors.fill: parent
                        radius: 27
                        color: Qt.rgba(1, 1, 1, 0.055)
                        border.color: Qt.rgba(1, 1, 1, 0.10)
                        border.width: 1
                    }
                    // failure flash overlay (opacity animated by failFx)
                    Rectangle {
                        anchors.fill: parent
                        radius: 27
                        color: "transparent"
                        border.color: "#ff6b6b"
                        border.width: 1.5
                        opacity: root.failFlash
                    }

                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 10

                        Text {
                            text: "\uF023"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 17
                            color: root.unlockInProgress ? "#8f959e" : "#e6e7e9"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        TextField {
                            id: field
                            width: 210
                            enabled: !root.unlockInProgress
                            focus: true
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 16
                            color: "#f8f8f2"
                            echoMode: TextInput.Password
                            placeholderText: "password"
                            placeholderTextColor: Qt.rgba(1, 1, 1, 0.28)
                            background: Rectangle { color: "transparent" }
                            anchors.verticalCenter: parent.verticalCenter
                            onTextChanged: root.currentText = this.text
                            onAccepted: root.tryUnlock()
                            Keys.onEscapePressed: Qt.quit()
                        }
                    }
                }

                // ── status line: verifying / failure / success ──
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.letterSpacing: 2
                    visible: root.unlockInProgress || root.showFailure || root.showSuccess
                    color: root.showSuccess ? "#7dcf9e"
                         : root.showFailure ? "#ff6b6b"
                         : Qt.rgba(1, 1, 1, 0.5)
                    text: root.showSuccess ? "PAM OK - WOULD UNLOCK"
                        : root.unlockInProgress ? "VERIFYING..."
                        : "INCORRECT PASSWORD"
                }
            }

            // hint
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                color: Qt.rgba(1, 1, 1, 0.22)
                text: "esc - close test window"
            }
        }
    }
}
