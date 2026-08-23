.pragma library

const API_BASE = "https://api.keeply.tools";

// Every response is a bounded list of bookmarks/folders/tags or a single
// small object; 5 MiB is generous even for a large account while still
// bounding what a faulty or compromised endpoint can force the shared
// shell process to hold in memory.
const MAX_RESPONSE_BYTES = 5 * 1024 * 1024;

// All requests are async — Quickshell's JS engine runs on the shell's UI
// thread, so a synchronous XHR here would freeze every bar and panel on
// every monitor for the duration of the network call.
function request(method, path, token, body, callback) {
  const xhr = new XMLHttpRequest();
  var responded = false;
  function respond(result, error) {
    if (responded) return;
    responded = true;
    callback(result, error);
  }
  xhr.onreadystatechange = function() {
    if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
      const lengthHeader = xhr.getResponseHeader("Content-Length");
      if (lengthHeader && parseInt(lengthHeader, 10) > MAX_RESPONSE_BYTES) {
        // abort() synchronously re-fires onreadystatechange (readyState
        // DONE, status 0), which would otherwise race this same respond()
        // call and win with a generic "Request failed (0)". Report first,
        // so that reentrant call finds responded already set and no-ops.
        respond(null, "Response too large");
        xhr.abort();
      }
      return;
    }
    if (xhr.readyState !== XMLHttpRequest.DONE) return;
    if (xhr.status >= 200 && xhr.status < 300) {
      if (xhr.responseText.length > MAX_RESPONSE_BYTES) {
        respond(null, "Response too large");
        return;
      }
      try {
        respond(JSON.parse(xhr.responseText), null);
      } catch (e) {
        respond(null, "Invalid response from server");
      }
    } else {
      respond(null, "Request failed (" + xhr.status + ")");
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
