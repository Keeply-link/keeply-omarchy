.pragma library

// The byte size of an API response is capped well before it reaches this
// module (see ApiBridge.qml/bin/keeply-api), but a small byte count doesn't
// bound shape: a "small" response can still be an array of hundreds of
// thousands of tiny records, or one record with a single pathological
// multi-kilobyte field. Both are still resource-exhaustion vectors once
// bound to a QML Repeater/Text, since each result becomes a real QML
// object tree and each field a real layout pass — so shape is capped here,
// at the last point before anything becomes UI-bound.
var MAX_RESULTS = 200;
var MAX_TAGS_PER_BOOKMARK = 20;
var MAX_TITLE_LENGTH = 500;
var MAX_URL_LENGTH = 2048;
var MAX_TEXT_FIELD_LENGTH = 1000;
var MAX_FOLDER_NAME_LENGTH = 200;
var MAX_TAG_NAME_LENGTH = 100;

function capString(value, maxLength) {
  var str = String(value || "");
  return str.length > maxLength ? str.substring(0, maxLength) : str;
}

function bookmarkToRow(bookmark) {
  var url = capString(bookmark.url, MAX_URL_LENGTH);
  var domain = getDomain(url);
  var folderName = "";
  var tagNames = [];

  if (bookmark.folder && typeof bookmark.folder === "object") {
    folderName = capString(bookmark.folder.name, MAX_FOLDER_NAME_LENGTH);
  }

  if (bookmark.tags) {
    for (var i = 0; i < bookmark.tags.length && tagNames.length < MAX_TAGS_PER_BOOKMARK; i++) {
      var tag = bookmark.tags[i];
      var tagName = (tag && tag.name) || (tag && tag.tag && tag.tag.name);
      if (tagName) {
        tagNames.push(capString(tagName, MAX_TAG_NAME_LENGTH));
      }
    }
  }

  return {
    id: bookmark.id || "",
    title: capString(bookmark.title, MAX_TITLE_LENGTH),
    url: url,
    domain: domain,
    description: capString(bookmark.description, MAX_TEXT_FIELD_LENGTH),
    note: capString(bookmark.note, MAX_TEXT_FIELD_LENGTH),
    imageUrl: capString(bookmark.imageUrl, MAX_URL_LENGTH),
    folderName: folderName,
    tagNames: tagNames,
    createdAt: bookmark.createdAt || "",
  };
}

// The only path any bookmark list should take on its way into a
// Repeater-bound property: caps how many records are rendered regardless
// of how many the server actually returned (the requested page `limit` is
// a request, not a guarantee — a malicious or non-compliant server isn't
// obligated to honor it).
function bookmarksToRows(bookmarks) {
  var list = bookmarks || [];
  var count = Math.min(list.length, MAX_RESULTS);
  var rows = [];
  for (var i = 0; i < count; i++) {
    rows.push(bookmarkToRow(list[i]));
  }
  return rows;
}

function getDomain(url) {
  try {
    var match = url.match(/^(?:https?:\/\/)?([^/?#]+)/);
    return match ? match[1] : url;
  } catch (e) {
    return url;
  }
}

function formatUrl(url) {
  if (url.length > 60) {
    return url.substring(0, 57) + "...";
  }
  return url;
}

function tagsToString(tagNames) {
  if (!tagNames || tagNames.length === 0) return "";
  return tagNames.join(", ");
}

function formatDate(dateStr) {
  if (!dateStr) return "";
  try {
    var date = new Date(dateStr);
    var now = new Date();
    var diff = now - date;
    var days = Math.floor(diff / (1000 * 60 * 60 * 24));

    if (days === 0) return "Today";
    if (days === 1) return "Yesterday";
    if (days < 7) return days + " days ago";
    if (days < 30) return Math.floor(days / 7) + "w ago";
    if (days < 365) return Math.floor(days / 30) + "mo ago";
    return Math.floor(days / 365) + "y ago";
  } catch (e) {
    return "";
  }
}
