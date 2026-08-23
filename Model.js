.pragma library

function bookmarkToRow(bookmark) {
  var title = bookmark.title || "";
  var url = bookmark.url || "";
  var domain = getDomain(url);
  var description = bookmark.description || "";
  var note = bookmark.note || "";
  var imageUrl = bookmark.imageUrl || "";
  var folderName = "";
  var tagNames = [];

  if (bookmark.folder) {
    folderName = bookmark.folder.name || "";
  } else if (typeof bookmark.folder === "object" && bookmark.folder !== null) {
    folderName = bookmark.folder.name || "";
  }

  if (bookmark.tags) {
    for (var i = 0; i < bookmark.tags.length; i++) {
      var tag = bookmark.tags[i];
      if (tag.name) {
        tagNames.push(tag.name);
      } else if (tag.tag && tag.tag.name) {
        tagNames.push(tag.tag.name);
      }
    }
  }

  return {
    id: bookmark.id || "",
    title: title,
    url: url,
    domain: domain,
    description: description,
    note: note,
    imageUrl: imageUrl,
    folderName: folderName,
    tagNames: tagNames,
    createdAt: bookmark.createdAt || "",
  };
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
