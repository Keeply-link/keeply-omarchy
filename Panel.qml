import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons

Panel {
  id: root

  moduleName: "io.github.rolfkoenders.keeply"
  ipcTarget: "io.github.rolfkoenders.keeply"

  readonly property string icon: String.fromCodePoint(0xF02E)
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  // A binding, not Component.onCompleted: `bar` is still null when this
  // Panel is instantiated and only gets assigned once the host bar mounts
  // the widget, so it re-evaluates once that happens.
  readonly property var service: bar ? bar.shell.serviceFor("io.github.rolfkoenders.keeply") : null
  property int cursorIndex: -1

  // The bar sizes this widget's slot from its implicit size, which a plain
  // Item never derives from an anchored-fill child on its own.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Connections {
    target: root.service
    function onCurrentResultsChanged() {
      root.cursorIndex = root.service.currentResults.length > 0 ? 0 : -1
    }
  }

  // Login verification and the initial bookmark fetch otherwise only ever
  // run once, right at startup. If either hits a transient failure,
  // there was no way to retry short of restarting the whole shell —
  // Service is a singleton that doesn't re-run its startup logic just
  // because the panel is reopened. retryIfNeeded() picks up whichever
  // one is still incomplete.
  onOpenedChanged: {
    if (root.opened && root.service) {
      root.service.retryIfNeeded();
    }
  }

  function setCursor(index) {
    root.cursorIndex = index
  }

  function moveCursor(dy) {
    if (!root.service || root.service.currentResults.length === 0) return
    var max = root.service.currentResults.length - 1
    var next = root.cursorIndex + dy
    root.cursorIndex = Math.max(0, Math.min(max, next))
  }

  function activateCursor() {
    if (!root.service) return
    var results = root.service.currentResults
    if (root.cursorIndex < 0 || root.cursorIndex >= results.length) return
    root.close();
    root.service.openBookmark(results[root.cursorIndex].url);
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    foreground: root.fg
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    open: root.opened
    anchorItem: button
    owner: root
    bar: root.bar
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.activateCursor()

      Column {
        id: column
        anchors.fill: parent

        PanelHero {
          width: parent.width
          title: "Keeply"
          foreground: root.fg
          fontFamily: root.family

          iconComponent: Text {
            textFormat: Text.PlainText
            text: root.icon
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.display
          }

          trailingControl: Component {
            Row {
              spacing: Style.space(4)

              PanelActionButton {
                iconText: String.fromCodePoint(0xF013)
                tooltipText: "Settings"
                foreground: root.fg
                onClicked: {
                  root.close();
                  root.bar.shell.summon("io.github.rolfkoenders.keeply", "{}");
                }
              }
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.fg }

        // Login prompt when not connected
        Column {
          visible: !root.service || !root.service.isLoggedIn
          width: parent.width
          topPadding: Style.space(16)
          spacing: Style.space(10)

          Text {
            text: "Connect to Keeply"
            font.family: root.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
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
            width: parent.width
            text: root.service && root.service.loading ? "Connecting..." : "Connect"
            enabled: !root.service || !root.service.loading
            bordered: true
            foreground: root.fg
            fontFamily: root.family
            onClicked: {
              if (root.service) root.service.login();
            }
          }

          Text {
            visible: root.service && root.service.errorMessage.length > 0
            text: root.service ? root.service.errorMessage : ""
            font.family: root.family
            font.pixelSize: Style.font.caption
            color: Color.urgent
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            width: parent.width
          }
        }

        // Search and results when logged in
        Column {
          visible: root.service && root.service.isLoggedIn
          width: parent.width
          topPadding: Style.space(16)
          spacing: Style.space(10)

          TextField {
            id: searchField
            width: parent.width
            placeholderText: "Search bookmarks..."
            foreground: root.fg
            font.family: root.family
            onTextChanged: {
              if (!root.service) return;
              if (text.length === 0) {
                // Clearing is instant and needs no network round-trip —
                // don't make it wait out the debounce.
                searchDebounce.stop();
                root.service.search(text);
              } else {
                searchDebounce.restart();
              }
            }

            Timer {
              id: searchDebounce
              interval: 250
              repeat: false
              onTriggered: {
                if (root.service) root.service.search(searchField.text);
              }
            }
            Keys.onDownPressed: function(event) {
              root.moveCursor(1)
              event.accepted = true
            }
            Keys.onUpPressed: function(event) {
              root.moveCursor(-1)
              event.accepted = true
            }
            Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
            Keys.onReturnPressed: function(event) { root.activateCursor(); event.accepted = true }
            Keys.onEnterPressed: function(event) { root.activateCursor(); event.accepted = true }
          }

          PanelSeparator { width: parent.width; foreground: root.fg }

          Text {
            visible: root.service && root.service.loading
            text: "Loading..."
            font.family: root.family
            font.pixelSize: Style.font.caption
            color: Color.muted
            textFormat: Text.PlainText
          }

          Text {
            visible: root.service && root.service.errorMessage.length > 0
            text: root.service ? root.service.errorMessage : ""
            font.family: root.family
            font.pixelSize: Style.font.caption
            color: Color.urgent
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Text {
            visible: root.service && root.service.currentResults.length > 0
            text: root.service && root.service.query.length > 0 ? "Results" : "Recent bookmarks"
            font.family: root.family
            font.pixelSize: Style.font.caption
            font.bold: true
            color: Color.muted
            textFormat: Text.PlainText
          }

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
                  required property var modelData
                  required property int index

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
                  hasCursor: index === root.cursorIndex
                  onCursorRequested: root.setCursor(index)
                  onOpenRequested: function(url) {
                    root.close();
                    root.service.openBookmark(url);
                  }
                }
              }
            }
          }

          Text {
            visible: root.service && root.service.currentResults.length === 0 && !root.service.loading && root.service.query.length > 0
            text: "No bookmarks found"
            font.family: root.family
            font.pixelSize: Style.font.caption
            color: Color.muted
            textFormat: Text.PlainText
          }
        }
      }
    }
  }
}
