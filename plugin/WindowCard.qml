import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// One window in the periphery: a live thumbnail at the window's aspect.
// Hovering selects it (the close and fullscreen keys then act on it). Click
// focuses it (switching workspace); dragging it into the focus area moves it
// onto the current workspace, onto another workspace group moves it there.
// Lines marked `qmllint disable missing-property` read the untyped theme
// singleton Style.
Item {
  id: card

  required property var win
  required property var host

  // The periphery selection: hovered, or reached with the focus keys.
  readonly property bool selected: host.selected === win.address && !dragging
  readonly property bool dragging: host.dragAddress === win.address

  Rectangle {
    anchors.fill: parent
    radius: card.host.windowRounding
    color: card.host.background
    visible: !thumb.hasContent

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.spacing.sm * 2 // qmllint disable missing-property
      textFormat: Text.PlainText
      text: card.win.appClass
      color: card.host.foreground
      opacity: 0.7
      font.family: card.host.fontFamily
      font.pixelSize: Style.font.caption // qmllint disable missing-property
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }

  ScreencopyView {
    id: thumb
    anchors.fill: parent
    captureSource: card.host.opened && card.win.toplevel ? card.win.toplevel.wayland : null
    live: card.host.opened
  }

  // The window's border, as Hyprland would draw it: active when selected.
  BorderOverlay {
    borderSpec: card.selected ? card.host.activeBorder : card.host.inactiveBorder
    radius: card.host.windowRounding
  }

  Rectangle {
    visible: card.selected
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.spacing.sm // qmllint disable missing-property
    width: Math.min(parent.width - Style.spacing.sm * 2, label.implicitWidth + Style.spacing.md * 2) // qmllint disable missing-property
    height: label.implicitHeight + Style.spacing.xs * 2 // qmllint disable missing-property
    radius: card.host.cornerRadius
    color: card.host.background

    Text {
      id: label
      anchors.centerIn: parent
      width: Math.min(implicitWidth, parent.width - Style.spacing.md * 2) // qmllint disable missing-property
      textFormat: Text.PlainText
      text: card.win.title || card.win.appClass
      color: card.host.selectedText
      font.family: card.host.fontFamily
      font.pixelSize: Style.font.caption // qmllint disable missing-property
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
    // Pointer input selects the card, also after the focus keys moved the
    // selection away while the pointer stayed here (latest input wins).
    onEntered: card.host.select(card.win.address)
    onPositionChanged: function(event) {
      if (!pressed) {
        if (!card.selected) card.host.select(card.win.address)
        return
      }
      var p = mapToItem(null, event.x, event.y)
      if (!moved && Math.abs(event.x - pressAt.x) + Math.abs(event.y - pressAt.y) < 8) return
      if (!moved) {
        moved = true
        card.host.beginDrag(card.win, card.width, card.height, pressAt.x, pressAt.y)
      }
      card.host.updateDrag(p.x, p.y)
    }
    onReleased: function(event) {
      if (moved) {
        var p = mapToItem(null, event.x, event.y)
        card.host.endDrag(p.x, p.y)
      } else {
        card.host.flyTo(card.win.address)
      }
      moved = false
    }
    onCanceled: {
      if (moved) card.host.cancelDrag()
      moved = false
    }
  }
}
