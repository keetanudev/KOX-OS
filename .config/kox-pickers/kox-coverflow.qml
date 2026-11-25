// coverflow.qml: shared visual picker for kox-wallpaper / kox-theme /
// kox-cursor. Run via: kox-coverflow <title> <initial-index> <json>
//   json = [{"label": "...", "image": "...", "bucket": "red|...|gray",
//           "accent": "#rrggbb"}, ...]  (bucket/accent optional)
// Reads entries from $KOX_CF_JSON, writes the chosen ORIG index to
// $KOX_CF_OUT (digits only), -1 on Esc (cancel).
// Optional env: KOX_CF_COLORFILTER=0 hides the color dots (cursor picker),
// KOX_CF_ACCENT sets the default center-card border, KOX_CF_TESTDIR runs
// a scripted tour (screenshots + select) for automated verification.
// Look: top filter pill (view toggle, slideshow, color dots, search) +
// slanted parallelogram cards, center card enlarged with accent border.
// Keys: Left/Right/h/l navigate, Up/Down in grid, g grid, space play,
// / focuses search, Return selects, Esc unfocus/cancel.
// Mouse: click focuses a card, double-click selects it.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
  id: root
  property var entries: JSON.parse(Quickshell.env("KOX_CF_JSON") || "[]")
  property string outPath: Quickshell.env("KOX_CF_OUT") || ""
  property string dlgTitle: Quickshell.env("KOX_CF_TITLE") || "Select"
  property int initial: parseInt(Quickshell.env("KOX_CF_INITIAL") || "0")
  property bool colorFiltering: (Quickshell.env("KOX_CF_COLORFILTER") || "1") !== "0"
  property string defAccent: Quickshell.env("KOX_CF_ACCENT") || "#e8e8ea"
  property string testDir: Quickshell.env("KOX_CF_TESTDIR") || ""
  property bool testCancel: (Quickshell.env("KOX_CF_TESTCANCEL") || "0") === "1"

  // One animation language for the whole picker.
  property int animDur: 200
  property int animEase: Easing.OutCubic

  property var dots: [
    { id: "red", c: "#ef4444" }, { id: "orange", c: "#f97316" },
    { id: "yellow", c: "#eab308" }, { id: "green", c: "#22c55e" },
    { id: "blue", c: "#3b82f6" }, { id: "purple", c: "#a855f7" },
    { id: "pink", c: "#ec4899" }, { id: "gray", c: "#9ca3af" }
  ]

  property var full: []
  property var shown: []
  property int sel: 0
  property string query: ""
  property string activeBucket: ""
  property bool gridMode: false
  property bool playing: false

  function dotColor(id) {
    for (var i = 0; i < dots.length; i++)
      if (dots[i].id === id) return dots[i].c;
    return defAccent;
  }

  function accentFor(entry) {
    if (!entry) return defAccent;
    if (entry.accent && entry.accent !== "") return entry.accent;
    if (entry.bucket && entry.bucket !== "") return dotColor(entry.bucket);
    return defAccent;
  }

  function buildFull() {
    var out = [];
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i] || {};
      out.push({
        label: e.label || ("item " + (i + 1)),
        image: e.image || "",
        bucket: e.bucket || "",
        accent: e.accent || "",
        orig: i
      });
    }
    full = out;
  }

  function applyFilter() {
    var q = query.toLowerCase();
    var kept = [];
    for (var i = 0; i < full.length; i++) {
      var e = full[i];
      if (activeBucket !== "" && e.bucket !== activeBucket) continue;
      if (q !== "" && e.label.toLowerCase().indexOf(q) === -1) continue;
      kept.push(e);
    }
    shown = kept;
    if (sel >= shown.length) sel = Math.max(0, shown.length - 1);
    if (sel < 0) sel = 0;
    rowView.centerNarrow();
    syncViews();
  }

  function syncViews() {
    rowView.currentIndex = sel;
    gridView.currentIndex = sel;
    rowView.positionViewAtIndex(sel, ListView.Center);
    if (gridView.count > 0)
      gridView.positionViewAtIndex(sel, GridView.Center);
  }

  function move(d) {
    if (shown.length === 0) return;
    sel = Math.max(0, Math.min(shown.length - 1, sel + d));
    syncViews();
  }

  function writeResult(value) {
    if (root.outPath !== "") {
      Quickshell.execDetached([
        "sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"",
        "kox-coverflow", String(value), root.outPath
      ]);
    }
    quitTimer.start();
  }

  function select(i) {
    if (!Number.isInteger(i) || i < 0 || i >= shown.length) return;
    playing = false;
    writeResult(shown[i].orig);
  }

  function cancel() {
    playing = false;
    writeResult(-1);
  }

  function toggleGrid() {
    gridMode = !gridMode;
    syncViews();
  }

  function togglePlay() {
    if (shown.length === 0) return;
    playing = !playing;
  }

  // Shared key handling: attached to both views and the search field.
  function handleKey(event) {
    var inSearch = searchBox.activeFocus;
    if (event.key === Qt.Key_Escape) {
      if (inSearch) {
        searchBox.focus = false;
        (gridMode ? gridView : rowView).forceActiveFocus();
      } else {
        cancel();
      }
      event.accepted = true;
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      select(sel);
      event.accepted = true;
    } else if (!inSearch && (event.key === Qt.Key_Slash || event.key === Qt.Key_Question)) {
      searchBox.forceActiveFocus();
      event.accepted = true;
    } else if (!inSearch && (event.key === Qt.Key_G || event.key === Qt.Key_Grave)) {
      toggleGrid();
      event.accepted = true;
    } else if (!inSearch && event.key === Qt.Key_Space) {
      togglePlay();
      event.accepted = true;
    } else if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
      move(-1);
      event.accepted = true;
    } else if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
      move(1);
      event.accepted = true;
    } else if (gridMode && event.key === Qt.Key_Up) {
      move(-gridView.cols);
      event.accepted = true;
    } else if (gridMode && event.key === Qt.Key_Down) {
      move(gridView.cols);
      event.accepted = true;
    } else if (event.key === Qt.Key_Home) {
      sel = 0;
      syncViews();
      event.accepted = true;
    } else if (event.key === Qt.Key_End) {
      sel = Math.max(0, shown.length - 1);
      syncViews();
      event.accepted = true;
    }
  }

  Timer {
    id: quitTimer
    interval: 150
    onTriggered: Qt.quit()
  }

  Timer {
    id: playTimer
    interval: 1600
    repeat: true
    running: playing
    onTriggered: {
      if (shown.length > 0) {
        sel = (sel + 1) % shown.length;
        syncViews();
      }
    }
  }

  Component.onCompleted: {
    buildFull();
    if (initial >= 0 && initial < full.length) sel = initial;
    applyFilter();
    rowView.forceActiveFocus();
    if (testDir !== "" || testCancel) testTimer.start();
  }

  // Scripted tour for automated verification (env-gated, no prod effect).
  Timer {
    id: testTimer
    interval: 700
    repeat: true
    property int step: 0
    onTriggered: {
      if (testCancel) { cancel(); return; }
      step++;
      if (step === 1) {
        stage.grabToImage(function(r) { r.saveToFile(testDir + "/row.png"); });
      } else if (step === 2) {
        gridMode = true; syncViews();
      } else if (step === 3) {
        stage.grabToImage(function(r) { r.saveToFile(testDir + "/grid.png"); });
      } else if (step === 4) {
        gridMode = false; query = "ocean"; searchBox.text = "ocean"; applyFilter();
      } else if (step === 5) {
        stage.grabToImage(function(r) { r.saveToFile(testDir + "/search.png"); });
      } else if (step === 6) {
        query = ""; searchBox.text = ""; activeBucket = "blue"; applyFilter();
      } else if (step === 7) {
        stage.grabToImage(function(r) { r.saveToFile(testDir + "/color.png"); });
      } else {
        testTimer.stop();
        query = ""; activeBucket = ""; applyFilter();
        select(0);
      }
    }
  }

  PanelWindow {
    id: win
    implicitWidth: win.screen != null ? win.screen.width : 1366
    implicitHeight: win.screen != null ? win.screen.height : 768
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      id: stage
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.78)

      // ---- top filter pill ----
      Rectangle {
        id: pill
        anchors { top: parent.top; topMargin: 30; horizontalCenter: parent.horizontalCenter }
        height: 42
        width: pillRow.width + 32
        radius: 21
        color: Qt.rgba(0.08, 0.08, 0.1, 0.95)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Row {
          id: pillRow
          anchors.centerIn: parent
          spacing: 8

          // view toggle (drawn grid icon)
          Rectangle {
            id: viewBtn
            width: 30; height: 30; radius: 8
            color: viewMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
            Grid {
              anchors.centerIn: parent
              columns: 2; rows: 2; spacing: 2
              Repeater {
                model: 4
                Rectangle { width: 6; height: 6; radius: 1.5; color: gridMode ? "#7dcfff" : "#e8e8ea" }
              }
            }
            MouseArea {
              id: viewMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: toggleGrid()
            }
          }

          // slideshow play/pause (drawn icons)
          Rectangle {
            id: playBtn
            width: 30; height: 30; radius: 8
            color: playMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
            Canvas {
              anchors.centerIn: parent
              width: 12; height: 12
              visible: !playing
              onPaint: {
                var c = getContext("2d");
                c.fillStyle = "#e8e8ea";
                c.beginPath();
                c.moveTo(2, 1); c.lineTo(11, 6); c.lineTo(2, 11);
                c.closePath(); c.fill();
              }
              Component.onCompleted: requestPaint()
            }
            Row {
              anchors.centerIn: parent
              spacing: 2
              visible: playing
              Rectangle { width: 3; height: 10; color: "#7dcfff" }
              Rectangle { width: 3; height: 10; color: "#7dcfff" }
            }
            MouseArea {
              id: playMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: togglePlay()
            }
          }

          Rectangle { width: 1; height: 20; color: Qt.rgba(1, 1, 1, 0.14); anchors.verticalCenter: parent.verticalCenter; visible: colorFiltering }

          // color filter dots
          Row {
            spacing: 7
            anchors.verticalCenter: parent.verticalCenter
            visible: colorFiltering
            Repeater {
              model: root.dots
              Rectangle {
                width: 15; height: 15; radius: 7.5
                anchors.verticalCenter: parent.verticalCenter
                color: modelData.c
                scale: root.activeBucket === modelData.id ? 1.25 : 1.0
                border.width: root.activeBucket === modelData.id ? 2 : 0
                border.color: "#ffffff"
                Behavior on scale { NumberAnimation { duration: root.animDur; easing.type: root.animEase } }
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    root.activeBucket = (root.activeBucket === modelData.id) ? "" : modelData.id;
                    root.applyFilter();
                  }
                }
              }
            }
          }

          Rectangle { width: 1; height: 20; color: Qt.rgba(1, 1, 1, 0.14); anchors.verticalCenter: parent.verticalCenter }

          // search field (drawn magnifier + text input)
          Rectangle {
            width: 140; height: 28; radius: 14
            anchors.verticalCenter: parent.verticalCenter
            color: searchBox.activeFocus ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
            Row {
              anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
              spacing: 6
              Item {
                width: 12; height: 12
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                  width: 8; height: 8; radius: 4
                  color: "transparent"
                  border.width: 1.6; border.color: "#a8a8b0"
                }
                Rectangle {
                  width: 5; height: 1.8
                  color: "#a8a8b0"
                  x: 7.2; y: 7.6
                  rotation: 45
                }
              }
              TextInput {
                id: searchBox
                width: 100
                anchors.verticalCenter: parent.verticalCenter
                color: "#f0f0f2"
                font.pixelSize: 12
                clip: true
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "filter…"
                  color: "#6e6e76"
                  font.pixelSize: 12
                  visible: searchBox.text === ""
                }
                onTextChanged: {
                  root.query = text;
                  root.applyFilter();
                }
                Keys.onPressed: (event) => root.handleKey(event)
              }
            }
            MouseArea {
              anchors.fill: parent
              onClicked: searchBox.forceActiveFocus()
            }
          }
        }
      }

      Text {
        anchors { top: pill.bottom; topMargin: 8; horizontalCenter: parent.horizontalCenter }
        text: root.dlgTitle
        color: "#8a8a92"
        font.pixelSize: 13
      }

      // ---- slanted-card row view ----
      ListView {
        id: rowView
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: 10 }
        height: 400
        orientation: ListView.Horizontal
        focus: true
        clip: true
        model: root.shown
        cacheBuffer: 3000
        highlightRangeMode: ListView.NoHighlightRange
        highlightMoveDuration: root.animDur
        visible: !gridMode
        opacity: gridMode ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: root.animDur; easing.type: root.animEase } }
        property bool cfReady: false
        property int stepW: 300
        // Card slot geometry: parallelogram top width 420, slant 56 over
        // height 280 (bounding 476). Slots tile at stepW so neighbours share
        // edges with no gaps; z-stacking (center on top) leaves side cards
        // as half parallelograms while the current one shows full.
        property int cardW: 420
        property int cardS: 56
        property int cardH: 280
        property int cardX: (stepW - (cardW + cardS)) / 2
        property int cardY: 60
        // Center narrow results: a ListView cannot scroll content that is
        // narrower than itself, so positionViewAtIndex(Center) leaves 1-2
        // filtered cards stuck left. Symmetric content margins do the job.
        function centerNarrow() {
          var pad = Math.max(0, (width - root.shown.length * stepW) / 2);
          leftMargin = pad;
          rightMargin = pad;
        }
        function widthHandler() {
          if (width <= 0) return;
          if (!cfReady) {
            cfReady = true;
            if (root.sel >= 0 && root.sel < count) currentIndex = root.sel;
          }
          centerNarrow();
          positionViewAtIndex(currentIndex, ListView.Center);
        }
        Component.onCompleted: widthHandler()
        onWidthChanged: widthHandler()

        delegate: Item {
          id: card
          width: rowView.stepW
          height: 400
          property bool isCur: ListView.isCurrentItem
          property int rel: index - rowView.currentIndex
          property string acc: root.accentFor(modelData)
          z: 1000 - Math.abs(rel) * 10
          onAccChanged: cardCanvas.requestPaint()
          onIsCurChanged: cardCanvas.requestPaint()

          Item {
            id: cardVis
            x: rowView.cardX
            y: rowView.cardY
            width: rowView.cardW + rowView.cardS
            height: rowView.cardH
            transformOrigin: Item.Center
            opacity: isCur ? 1.0 : 0.62
            scale: isCur ? 1.1 : 0.9
            Behavior on opacity { NumberAnimation { duration: root.animDur; easing.type: root.animEase } }
            Behavior on scale { NumberAnimation { duration: root.animDur; easing.type: root.animEase } }

            // Card face: rim fill + parallelogram-cropped image, painted by
            // ONE Canvas (pure QtQuick 2D). The rice layered a Canvas rim +
            // OpacityMask (Qt5Compat) over an offscreen Image/ShaderEffectSource
            // pair; this Artix quickshell build ships neither Qt5Compat nor
            // runtime shader transpilation (fragmentShader expects a
            // precompiled .qsb), so the mask work moved into the same 2D
            // canvas as the rim. The source Image is hidden and loaded
            // SYNCHRONOUSLY (invisible async images do not reliably decode
            // here) — cheap because kox-wallpaper/kox-theme feed small
            // pre-scaled ffmpeg thumbs; full-res paths only occur when
            // ffmpeg is absent on the machine.
            Canvas {
              id: cardCanvas
              anchors.fill: parent
              property var srcItem: srcImg
              onPaint: {
                var c = getContext("2d");
                var W = rowView.cardW, S = rowView.cardS, H = rowView.cardH;
                c.clearRect(0, 0, width, height);
                // Rim: accent fill for the current card, faint neutral for
                // the rest so dark cards stay visibly bounded on dark dim.
                c.fillStyle = isCur ? card.acc : Qt.rgba(1, 1, 1, 0.16);
                c.beginPath();
                c.moveTo(S, 0); c.lineTo(S + W, 0); c.lineTo(W, H); c.lineTo(0, H);
                c.closePath(); c.fill();
                // Image face: center-cover crop, clipped to the rim inset
                // (5px sides / 3px top+bottom) so the border shows.
                if (srcItem.status === Image.Ready && srcItem.implicitWidth > 0) {
                  c.save();
                  c.beginPath();
                  c.moveTo(S + 5, 3); c.lineTo(S + W - 5, 3);
                  c.lineTo(W - 5, H - 3); c.lineTo(5, H - 3);
                  c.closePath(); c.clip();
                  var iw = srcItem.implicitWidth, ih = srcItem.implicitHeight;
                  var boxAR = (W + S) / H, imgAR = iw / ih;
                  var sx = 0, sy = 0, sw = iw, sh = ih;
                  if (imgAR > boxAR) { sw = ih * boxAR; sx = (iw - sw) / 2; }
                  else { sh = iw / boxAR; sy = (ih - sh) / 2; }
                  c.drawImage(srcItem, sx, sy, sw, sh, 0, 0, W + S, H);
                  c.restore();
                }
              }
              Component.onCompleted: requestPaint()
            }

            // Hidden synchronous source for the card face above. No fillMode:
            // the Canvas drawImage source coords address the NATURAL image,
            // and PreserveAspectCrop would hand the canvas an already-cropped
            // frame, making the crop rect out of bounds (draws nothing).
            Image {
              id: srcImg
              anchors.fill: parent
              source: "file://" + modelData.image
              cache: true
              asynchronous: false
              visible: false
              onStatusChanged: cardCanvas.requestPaint()
              onSourceChanged: cardCanvas.requestPaint()
            }
          }

          MouseArea {
            x: rowView.cardX
            y: rowView.cardY
            width: rowView.cardW + rowView.cardS
            height: rowView.cardH
            onClicked: {
              root.sel = index;
              rowView.currentIndex = index;
              rowView.positionViewAtIndex(index, ListView.Center);
            }
            onDoubleClicked: root.select(index)
          }
        }

        Keys.onPressed: (event) => root.handleKey(event)
      }

      // ---- grid view (same model, same selection) ----
      GridView {
        id: gridView
        anchors { top: pill.bottom; topMargin: 52; bottom: curLabel.top; bottomMargin: 8; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width - 120, 1180)
        clip: true
        model: root.shown
        property int cols: Math.max(1, Math.floor(width / cellWidth))
        cellWidth: 224
        cellHeight: 178
        focus: false
        visible: gridMode
        opacity: gridMode ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.animDur; easing.type: root.animEase } }

        delegate: Item {
          width: gridView.cellWidth
          height: gridView.cellHeight
          property bool isCur: GridView.isCurrentItem
          Image {
            width: 200
            height: 132
            anchors.centerIn: parent
            source: "file://" + modelData.image
            fillMode: Image.PreserveAspectCrop
            cache: true
            asynchronous: true
            opacity: isCur ? 1.0 : 0.55
            scale: isCur ? 1.06 : 0.94
            Behavior on opacity { NumberAnimation { duration: root.animDur; easing.type: root.animEase } }
            Behavior on scale { NumberAnimation { duration: root.animDur; easing.type: root.animEase } }
            Rectangle {
              anchors.fill: parent
              color: "transparent"
              border.width: isCur ? 3 : 0
              border.color: root.accentFor(modelData)
            }
          }
          MouseArea {
            anchors.fill: parent
            onClicked: {
              root.sel = index;
              gridView.currentIndex = index;
            }
            onDoubleClicked: root.select(index)
          }
        }

        Keys.onPressed: (event) => root.handleKey(event)
      }

      Text {
        id: curLabel
        anchors { bottom: hintText.top; bottomMargin: 4; horizontalCenter: parent.horizontalCenter }
        text: (shown.length > 0 && sel >= 0 && sel < shown.length) ? shown[sel].label : (query !== "" || activeBucket !== "" ? "no match" : "")
        color: "#ffffff"
        font.pixelSize: 22
      }

      Text {
        id: hintText
        anchors { bottom: parent.bottom; bottomMargin: 26; horizontalCenter: parent.horizontalCenter }
        text: "Left/Right navigate · Enter apply · / filter · g grid · space play · Esc cancel"
        color: "#8a8a90"
        font.pixelSize: 13
      }
    }
  }
}
