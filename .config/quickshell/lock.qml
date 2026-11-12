// KOX OS lockscreen — real session lock (WlSessionLock + PAM).
//
// The session is locked the instant this file loads (locked: true); the
// compositor guarantees this surface covers every monitor above all other
// clients, blocks screen capture, and routes all input here. A successful
// PAM auth releases the lock, then the process quits. Strict order:
// locked = false BEFORE Qt.quit() — quitting while still locked would make
// the compositor kill the session.
//
// Spawned on demand by ~/.local/bin/kox-lock (Super+Ctrl+L) — no resident
// daemon, zero idle RAM. PAM policy is user-owned:
// ~/.config/quickshell/pam/lock.conf (auth required pam_unix.so).
//
//   quickshell -p ~/.config/quickshell/lock.qml
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam

Scope {
    id: root

    signal unlocked()
    signal failed()

    // Shared auth state — every monitor surface renders the same
    // text/failure state through these bindings.
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property real failFlash: 0
    // shake is animated as a shared property: every monitor surface binds
    // its pill to this, so the animation never references surface-internal
    // ids (surfaces are created per-screen and only exist while locked).
    property real shakeX: 0

    onCurrentTextChanged: showFailure = false

    function tryUnlock() {
        if (currentText === "" || unlockInProgress)
            return
        unlockInProgress = true
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
        console.log("KOX-LOCK: PAM SUCCESS - unlocking the session")
        // Strict order: release the session lock first, then quit.
        lock.locked = false
        Qt.quit()
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
            NumberAnimation { target: root; property: "shakeX"; to: -9; duration: 45 }
            NumberAnimation { target: root; property: "shakeX"; to: 9; duration: 45 }
            NumberAnimation { target: root; property: "shakeX"; to: -6; duration: 45 }
            NumberAnimation { target: root; property: "shakeX"; to: 6; duration: 45 }
            NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 45 }
        }
    }

    WlSessionLock {
        id: lock
        locked: true

        // One surface per connected monitor, created automatically.
        WlSessionLockSurface {
            Rectangle {
                anchors.fill: parent
                color: "#0c0e12"
                focus: true

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
                        transform: Translate { x: root.shakeX }

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
                            }
                        }
                    }

                    // ── status line: verifying / failure ──
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.letterSpacing: 2
                        visible: root.unlockInProgress || root.showFailure
                        color: root.showFailure ? "#ff6b6b" : Qt.rgba(1, 1, 1, 0.5)
                        text: root.unlockInProgress ? "VERIFYING..." : "INCORRECT PASSWORD"
                    }
                }
            }
        }
    }
}
