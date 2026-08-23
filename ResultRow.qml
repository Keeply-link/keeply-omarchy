import QtQuick
import qs.Ui
import qs.Commons

CursorSurface {
  id: root

  required property string bookmarkId
  required property string bookmarkTitle
  required property string bookmarkUrl
  required property string bookmarkDomain
  required property string bookmarkDescription
  required property string bookmarkNote
  required property string bookmarkImageUrl
  required property string bookmarkFolderName
  required property var bookmarkTagNames
  required property string bookmarkCreatedAt

  signal openRequested(string url)

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  implicitHeight: row.implicitHeight + Style.space(16)

  function displayTags() {
    if (!bookmarkTagNames || bookmarkTagNames.length === 0) return "";
    var tags = [];
    var limit = Math.min(bookmarkTagNames.length, 3);
    for (var i = 0; i < limit; i++) {
      tags.push(bookmarkTagNames[i]);
    }
    if (bookmarkTagNames.length > 3) {
      tags.push("+" + (bookmarkTagNames.length - 3));
    }
    return tags.join(", ");
  }

  Row {
    id: row
    anchors.fill: parent
    anchors.margins: Style.space(8)
    spacing: Style.space(10)

    // Favicon / domain icon
    Rectangle {
      width: 24
      height: 24
      radius: 4
      color: Color.muted
      anchors.verticalCenter: parent.verticalCenter

      Text {
        anchors.centerIn: parent
        text: root.bookmarkDomain.charAt(0).toUpperCase()
        font.family: root.family
        font.pixelSize: 12
        font.bold: true
        color: root.fg
      }
    }

    // Content
    Column {
      width: parent.width - 24 - Style.space(10)
      spacing: 2

      Text {
        width: parent.width
        text: root.bookmarkTitle || root.bookmarkDomain
        font.family: root.family
        font.pixelSize: Style.font.body
        color: root.fg
        elide: Text.ElideRight
        maximumLineCount: 1
        textFormat: Text.PlainText
      }

      Row {
        spacing: Style.space(6)

        Text {
          text: root.bookmarkDomain
          font.family: root.family
          font.pixelSize: Style.font.caption
          color: Color.muted
          textFormat: Text.PlainText
        }

        Text {
          visible: root.bookmarkFolderName.length > 0
          text: "| " + root.bookmarkFolderName
          font.family: root.family
          font.pixelSize: Style.font.caption
          color: Color.muted
          textFormat: Text.PlainText
        }

        Text {
          visible: displayTags().length > 0
          text: "| " + displayTags()
          font.family: root.family
          font.pixelSize: Style.font.caption
          color: Color.accent
          textFormat: Text.PlainText
        }
      }
    }
  }

  onClicked: {
    root.openRequested(root.bookmarkUrl);
  }
}
