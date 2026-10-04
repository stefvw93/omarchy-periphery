import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// One window in the periphery: a live thumbnail at the window's aspect.
// Click focuses it (switching workspace); dragging it into the focus area
// moves it onto the current workspace, onto another workspace group moves
// it there.
Item {
  id: card

  required property var win
  required property var host

  readonly property bool hovered: mouse.containsMouse && !dragging
  readonly property bool dragging: host.dragAddress === win.address

  Rectangle {
    anchors.fill: parent
    radius: host.cornerRadius
    color: host.background
    border.color: host.border
    border.width: 1
    visible: !thumb.hasContent

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.spacing.sm * 2
      textFormat: Text.PlainText
      text: card.win.appClass
      color: host.foreground
      opacity: 0.7
      font.family: host.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }

  ScreencopyView {
    id: thumb
    anchors.fill: parent
    captureSource: host.opened && card.win.toplevel ? card.win.toplevel.wayland : null
    live: host.opened
  }

  Rectangle {
    anchors.fill: parent
    radius: host.cornerRadius
    color: "transparent"
    border.color: host.accent
    border.width: Math.max(2, Style.space(2))
    visible: card.hovered
  }

  Rectangle {
    visible: card.hovered
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.spacing.sm
    width: Math.min(parent.width - Style.spacing.sm * 2, label.implicitWidth + Style.spacing.md * 2)
    height: label.implicitHeight + Style.spacing.xs * 2
    radius: host.cornerRadius
    color: host.background

    Text {
      id: label
      anchors.centerIn: parent
      width: Math.min(implicitWidth, parent.width - Style.spacing.md * 2)
      textFormat: Text.PlainText
      text: card.win.title || card.win.appClass
      color: host.selectedText
      font.family: host.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: card.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

    property point pressAt
    property bool moved: false

    onPressed: function(event) {
      pressAt = Qt.point(event.x, event.y)
      moved = false
    }
    onPositionChanged: function(event) {
      if (!pressed) return
      var p = mapToItem(null, event.x, event.y)
      if (!moved && Math.abs(event.x - pressAt.x) + Math.abs(event.y - pressAt.y) < 8) return
      if (!moved) {
        moved = true
        host.beginDrag(card.win, card.width, card.height, pressAt.x, pressAt.y)
      }
      host.updateDrag(p.x, p.y)
    }
    onReleased: function(event) {
      if (moved) {
        var p = mapToItem(null, event.x, event.y)
        host.endDrag(p.x, p.y)
      } else {
        host.flyTo(card.win.address)
      }
      moved = false
    }
    onCanceled: {
      if (moved) host.cancelDrag()
      moved = false
    }
  }
}
