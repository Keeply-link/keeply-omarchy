import QtQuick
import qs.Ui
import qs.Commons

Item {
  id: root

  property var shell
  property var manifest
  property var service: null

  Component.onCompleted: {
    service = shell.serviceFor("keeply");
  }

  Rectangle {
    anchors.fill: parent
    color: Color.popups.background

    Column {
      anchors.centerIn: parent
      spacing: Style.space(16)
      width: Math.min(parent.width - Style.space(32), 400)

      // Header
      Text {
        text: "Keeply Settings"
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
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
          anchors.horizontalCenter: parent.horizontalCenter
          onClicked: {
            if (root.service) root.service.logout();
          }
        }
      }
    }
  }
}
