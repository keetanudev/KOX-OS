// KOX OS lockscreen — real session lock (WlSessionLock + PAM).
//
// Choreography (all on-demand, no resident daemon):
//   1. kox-lock (Super+Ctrl+L) spawns this file.
//   2. A fullscreen "veil" layer overlay fades the desktop to dark
//      (QML-driven opacity) while the engine warms up — the keypress
//      reads as a fluid dim, not a hard cut.
//   3. ~330 ms in, the session lock engages; the compositor blanks the
//      near-black screen for the frame or two the lock surface needs,
//      and the veil is retired shortly after the surface presents.
//   4. The clock/date/pill bloom in (staggered fade + rise).
//   5. Correct password: the UI collapses (~160 ms), the lock releases,
//      then the process quits. Strict order: locked=false BEFORE
//      Qt.quit() — quitting while locked would make the compositor kill
//      the session.
//
// Focus: the password field force-grabs active focus on surface creation
// (plus timed retries and click-anywhere refocus) — no click needed to
// start typing.
//
// The lockscreen UI lives in ONE Component shared by the session-lock
// surface and the dry-run check window, so test and production paths
// cannot drift and delegate-path bugs surface during dry-runs.
//
// Test hook: KOX_LOCK_DRY=1 loads the file without mapping the veil or
// engaging the lock, and renders the exact surface content in a plain
// check window instead.
//
// PAM policy: ~/.config/quickshell/pam/lock.conf (user-owned,
// auth required pam_unix.so).
//
//   quickshell -p ~/.config/quickshell/lock.qml
import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam

Scope {
    id: root

    readonly property bool dryRun: Quickshell.env("KOX_LOCK_DRY") === "1"

    signal unlocked()
    signal failed()

    // ── shared auth state (every monitor surface binds to these) ──
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property real failFlash: 0
    // shake + entrance are shared properties so animations never
    // reference ids inside per-screen surfaces.
    property real shakeX: 0
    property real uiClock: 0
    property real uiDate: 0
    property real uiPill: 0

    // ── veil choreography state ──
    property bool veilUp: false
    property real veilOpacity: 0

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

    Component.onCompleted: {
        root.veilUp = true
        veilFx.restart()
        engageTimer.restart()
    }
    onUnlocked: {
        console.log("KOX-LOCK: PAM SUCCESS - unlocking the session")
        exitFx.restart()
    }
    onFailed: {
        showFailure = true
        console.log("KOX-LOCK: PAM failed - clearing entry")
        failFx.restart()
    }

    // ── pre-lock veil: fullscreen dim overlay (single screen) ──
    // Keyboard-grabbing so muscle-memory typing during the handover is
    // swallowed instead of leaking into the focused app.
    PanelWindow {
        id: veil
        visible: root.veilUp && !root.dryRun
        color: "transparent"
        aboveWindows: true
        focusable: true
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }

        Rectangle {
            anchors.fill: parent
            color: "#0c0e12"
            opacity: root.veilOpacity
        }
    }

    NumberAnimation {
        id: veilFx
        target: root
        property: "veilOpacity"
        to: 1
        duration: 300
        easing.type: Easing.OutCubic
    }

    // engage the session lock once the veil has covered the screen
    Timer {
        id: engageTimer
        interval: 330
        onTriggered: if (!root.dryRun) lock.locked = true
    }

    // ── entrance: clock blooms in, then date, then pill ──
    SequentialAnimation {
        id: enterFx
        PauseAnimation { duration: 90 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "uiClock"; to: 1; duration: 430; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 120 }
                NumberAnimation { target: root; property: "uiDate"; to: 1; duration: 380; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: 200 }
                NumberAnimation { target: root; property: "uiPill"; to: 1; duration: 380; easing.type: Easing.OutCubic }
            }
        }
    }

    // ── exit: collapse the UI, then release the lock and quit ──
    SequentialAnimation {
        id: exitFx
        ParallelAnimation {
            NumberAnimation { target: root; property: "uiClock"; to: 0; duration: 160; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "uiDate"; to: 0; duration: 160; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "uiPill"; to: 0; duration: 160; easing.type: Easing.InQuad }
        }
        ScriptAction {
            script: {
                // strict order: release the session lock first, then quit.
                lock.locked = false
                Qt.quit()
            }
        }
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

    // ── the lockscreen UI: one definition, two consumers ──
    // Instantiated inside every WlSessionLockSurface (per monitor) and in
    // the dry-run check window. Bindings and animations target shared
    // root properties only — no cross-surface id references.
    Component {
        id: lockUi

        Rectangle {
            anchors.fill: parent
            color: "#0c0e12"

            Component.onCompleted: {
                enterFx.restart()
                veilClose.restart()
            }

            // retire the veil a beat after the surface presents
            Timer {
                id: veilClose
                interval: 90
                onTriggered: root.veilUp = false
            }

            // keyboard focus: grab on creation + timed retries so the
            // password field is ready to type without any click.
            Timer { interval: 120; running: true; onTriggered: field.forceActiveFocus() }
            Timer { interval: 420; running: true; onTriggered: field.forceActiveFocus() }

            // click anywhere -> back to the password field
            MouseArea {
                anchors.fill: parent
                onClicked: field.forceActiveFocus()
            }

            Column {
                anchors.centerIn: parent
                spacing: 24

                // ── clock: Nothing OS dot-matrix face, big hours ──
                Text {
                    id: clock
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.RichText
                    // Ndot 57 — Nothing's classic dot-matrix typeface
                    // (nothing.tech). Proprietary (community-ripped);
                    // installed locally — NEVER commit the binary.
                    font.family: "Ndot 57"
                    opacity: root.uiClock
                    transform: Translate { y: (1 - root.uiClock) * 14 }
                    property var now: new Date()
                    text: "<span style=\"font-size:190px; color:#f8f8f2\">"
                          + Qt.formatDateTime(now, "HH")
                          + "</span><span style=\"font-size:110px; color:rgba(248,248,242,0.55)\">"
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
                    opacity: root.uiDate
                    transform: Translate { y: (1 - root.uiDate) * 10 }
                    text: Qt.formatDateTime(clock.now, "dddd · MMMM d").toString().toUpperCase()
                }

                // ── password pill ──
                Item {
                    id: pillWrap
                    width: pillRow.width + 44
                    height: 54
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: root.uiPill
                    transform: Translate { x: root.shakeX; y: (1 - root.uiPill) * 12 }

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
                    opacity: root.uiPill
                    color: root.showFailure ? "#ff6b6b" : Qt.rgba(1, 1, 1, 0.5)
                    text: root.unlockInProgress ? "VERIFYING..." : "INCORRECT PASSWORD"
                }
            }
        }
    }

    WlSessionLock {
        id: lock
        // engaged by engageTimer once the veil has faded over the desktop
        locked: false

        // One surface per connected monitor, created automatically.
        WlSessionLockSurface {
            Loader {
                anchors.fill: parent
                sourceComponent: lockUi
            }
        }
    }

    // ── dry-run check window: renders the exact surface content in a
    // plain window so delegate-path bugs surface during testing without
    // ever touching the real session. Never maps on a real lock. ──
    Window {
        visible: root.dryRun
        title: "KOX lock check"
        width: 480
        height: 700
        color: "#0c0e12"
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint

        Loader {
            anchors.fill: parent
            active: root.dryRun
            sourceComponent: lockUi
        }
    }
}
