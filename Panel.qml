import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

Panel {
  id: root

  moduleName: "keeply"
  ipcTarget: "keeply"

  readonly property string icon: String.fromCodePoint(0xF02E)
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  property var service: null

  Component.onCompleted: {
    service = bar.shell.serviceFor("keeply");
  }

  BarIconButton {
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    foreground: root.fg
    onPressed: root.toggle()
  }

  KeyboardPanel {
    open: root.opened
    anchorItem: button
    owner: root
    bar: root.bar
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onActivateRequested: root.expandCursor()
      onTextKey: function(key) {
        searchField.text += key;
        searchField.cursorPosition = searchField.text.length;
      }
      onBackspaceRequested: {
        if (searchField.text.length > 0) {
          searchField.text = searchField.text.slice(0, -1);
        }
      }

      Column {
        id: column
        width: parent.width

        PanelHero {
          title: "Keeply"
          icon: root.icon

          trailing: Row {
            spacing: Style.space(4)

            PanelActionButton {
              icon: String.fromCodePoint(0xF013)
              tooltip: "Settings"
              onClicked: {
                root.close();
                root.showOverlay("keeply");
              }
            }
          }
        }

        PanelSeparator {}

        // Login prompt when not connected
        Column {
          visible: !root.service || !root.service.isLoggedIn
          width: parent.width
          padding: Style.space(16)
          spacing: Style.space(8)

          Text {
            text: "Connect to Keeply"
            font.family: root.family
            font.pixelSize: Style.font.body
            color: root.fg
            textFormat: Text.PlainText
          }

          Text {
            text: "Sign in to search and browse your bookmarks."
            font.family: root.family
            font.pixelSize: Style.font.caption
            color: Color.muted
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Button {
            text: "Connect"
            onClicked: {
              if (root.service) root.service.login();
            }
          }
        }

        // Search and results when logged in
        Column {
          visible: root.service && root.service.isLoggedIn
          width: parent.width

          TextField {
            id: searchField
            width: parent.width
            placeholderText: "Search bookmarks..."
            font.family: root.family
            onTextChanged: {
              if (root.service) root.service.search(text);
            }
          }

          PanelSeparator {}

          // Loading indicator
          Text {
            visible: root.service && root.service.loading
            text: "Loading..."
            font.family: root.family
            font.pixelSize: Style.font.caption
            color: Color.muted
            padding: Style.space(8)
            textFormat: Text.PlainText
          }

          // Error message
          Text {
            visible: root.service && root.service.errorMessage.length > 0
            text: root.service ? root.service.errorMessage : ""
            font.family: root.family
            font.pixelSize: Style.font.caption
            color: Color.urgent
            padding: Style.space(8)
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            width: parent.width
          }

          // Results list
          ScrollView {
            width: parent.width
            height: Math.min(resultColumn.implicitHeight + Style.space(16), Style.space(400))
            clip: true
            visible: root.service && root.service.currentResults.length > 0

            Column {
              id: resultColumn
              width: parent.width

              Repeater {
                model: root.service ? root.service.currentResults : []
                delegate: ResultRow {
                  width: resultColumn.width
                  bookmarkId: modelData.id
                  bookmarkTitle: modelData.title
                  bookmarkUrl: modelData.url
                  bookmarkDomain: modelData.domain
                  bookmarkDescription: modelData.description
                  bookmarkNote: modelData.note
                  bookmarkImageUrl: modelData.imageUrl
                  bookmarkFolderName: modelData.folderName
                  bookmarkTagNames: modelData.tagNames
                  bookmarkCreatedAt: modelData.createdAt
                  bar: root.bar
                  onOpenRequested: function(url) {
                    root.close();
                    root.service.openBookmark(url);
                  }
                }
              }
            }
          }

          // Empty state
          Text {
            visible: root.service && root.service.currentResults.length === 0 && !root.service.loading && root.service.query.length > 0
            text: "No bookmarks found"
            font.family: root.family
            font.pixelSize: Style.font.caption
            color: Color.muted
            padding: Style.space(16)
            textFormat: Text.PlainText
          }

          // Account info footer
          PanelSeparator {}

          Row {
            width: parent.width
            padding: Style.space(8)
            spacing: Style.space(8)

            Text {
              text: root.service ? root.service.user : ""
              font.family: root.family
              font.pixelSize: Style.font.caption
              color: Color.muted
              textFormat: Text.PlainText
              elide: Text.ElideRight
              width: parent.width - logoutButton.width - Style.space(8)
            }

            Button {
              id: logoutButton
              text: "Sign out"
              onClicked: {
                if (root.service) root.service.logout();
              }
            }
          }
        }
      }
    }
  }
}
