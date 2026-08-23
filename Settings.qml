import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Ui
import qs.Commons

// Overlay-kind plugins must host their own layer-shell window — the shell's
// panel loader just parents this Item into the object tree, it doesn't wrap
// it in a window. Without the PanelWindow below, this content would exist
// but never actually appear on screen (matches the reminders/clipboard/
// image-picker first-party overlays' shape).
Item {
  id: root

  property var shell
  property var manifest
  // Not readonly: the shell's overlay loader assigns this directly after
  // mounting (`item.service = ...`), alongside `shell`/`manifest` above.
  // The binding here is just the fallback for whenever `shell` alone is set.
  property var service: shell ? shell.serviceFor("io.github.rolfkoenders.keeply") : null

  property bool opened: false

  // Lifecycle hooks invoked by the shell's summon/hide (shell.summon(id,
  // payloadJson) hands the JSON to open() here; shell.hide(id) calls close()).
  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "keeply-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()
    }

    BorderSurface {
      id: dialog
      anchors.centerIn: parent
      width: Math.min(400, parent.width - Style.space(32))
      implicitHeight: card.implicitHeight + contentTopInset + contentBottomInset
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: Style.space(24)

      // Swallow clicks so they don't bubble to the scrim's dismiss handler.
      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Column {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: dialog.contentLeftInset
        anchors.rightMargin: dialog.contentRightInset
        anchors.topMargin: dialog.contentTopInset
        spacing: Style.space(16)

        Text {
          text: "Keeply Settings"
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
          color: Color.foreground
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
        }

        // Not logged in
        Column {
          visible: !root.service || !root.service.isLoggedIn
          width: parent.width
          spacing: Style.space(12)

          Text {
            text: "Connect your Keeply account to search and browse bookmarks from the menu bar."
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: Color.muted
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
          }

          Button {
            text: "Connect to Keeply"
            bordered: true
            anchors.horizontalCenter: parent.horizontalCenter
            onClicked: {
              if (root.service) root.service.login();
            }
          }

          Text {
            visible: root.service && root.service.errorMessage.length > 0
            text: root.service ? root.service.errorMessage : ""
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.urgent
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
          }
        }

        // Logged in
        Column {
          visible: root.service && root.service.isLoggedIn
          width: parent.width
          spacing: Style.space(12)

          Text {
            text: "Connected as"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            text: root.service ? root.service.user : ""
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: Color.foreground
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }

          Button {
            text: "Sign out"
            bordered: true
            anchors.horizontalCenter: parent.horizontalCenter
            onClicked: {
              if (root.service) root.service.logout();
            }
          }
        }
      }
    }
  }
}
