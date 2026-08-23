.pragma library

const API_BASE = "https://api.keeply.tools";

// All requests are async — Quickshell's JS engine runs on the shell's UI
// thread, so a synchronous XHR here would freeze every bar and panel on
// every monitor for the duration of the network call.
function request(method, path, token, body, callback) {
  const xhr = new XMLHttpRequest();
  xhr.onreadystatechange = function() {
    if (xhr.readyState !== XMLHttpRequest.DONE) return;
    if (xhr.status >= 200 && xhr.status < 300) {
      try {
        callback(JSON.parse(xhr.responseText), null);
      } catch (e) {
        callback(null, "Invalid response from server");
      }
    } else {
      callback(null, "Request failed (" + xhr.status + ")");
    }
  };
  xhr.open(method, API_BASE + path);
  xhr.setRequestHeader("Authorization", "ApiKey " + token);
  xhr.setRequestHeader("Content-Type", "application/json");
  xhr.send(body ? JSON.stringify(body) : undefined);
}

function verifyToken(token, callback) {
  request("GET", "/users/me", token, null, callback);
}

function searchBookmarks(token, query, page, limit, callback) {
  page = page || 1;
  limit = limit || 30;
  const params = "?q=" + encodeURIComponent(query) + "&page=" + page + "&limit=" + limit;
  request("GET", "/search" + params, token, null, callback);
}

function fetchBookmarks(token, page, limit, sort, callback) {
  page = page || 1;
  limit = limit || 30;
  sort = sort || "date-desc";
  const params = "?page=" + page + "&limit=" + limit + "&sort=" + sort;
  request("GET", "/bookmarks" + params, token, null, callback);
}

function fetchFolders(token, callback) {
  request("GET", "/folders", token, null, callback);
}

function fetchTags(token, callback) {
  request("GET", "/tags", token, null, callback);
}

function fetchSidebarData(token, callback) {
  request("GET", "/bookmarks/sidebar-data", token, null, callback);
}
