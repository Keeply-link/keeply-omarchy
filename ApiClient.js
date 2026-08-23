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
  // Checking responseText.length only at DONE is too late: Qt's QML XHR
  // buffers the entire body into responseText as it streams in (verified
  // empirically — it grows across many LOADING events well before DONE),
  // so by the time DONE fires an oversized response has already been
  // fully held in memory regardless of what we do with it afterward.
  // Checking on every LOADING event and aborting the moment the cap is
  // crossed actually bounds what gets buffered instead of just bounding
  // what gets parsed.
  //
  // Deliberately NOT using the Content-Length header to reject early at
  // HEADERS_RECEIVED: verified empirically (headless qml6 + a real slow
  // streaming server) that calling xhr.abort() that early — before any
  // body data has buffered into responseText — reproducibly segfaults
  // Qt's QNetworkReply internals. Waiting for actual buffered bytes to
  // cross the cap before aborting is what the memory-exhaustion concern
  // actually requires anyway (the header is just a server-supplied claim,
  // not memory pressure), so this loses no protection.
  function rejectIfOversized() {
    // abort() re-fires onreadystatechange synchronously (see below), which
    // re-enters this same function — without this, that reentrant call
    // would see the same still-oversized responseText and call abort()
    // again, forever.
    if (responded) return true;
    if (!xhr.responseText || xhr.responseText.length <= MAX_RESPONSE_BYTES) return false;
    // abort() synchronously re-fires onreadystatechange (readyState DONE,
    // status 0), which would otherwise race this same respond() call and
    // win with a generic "Request failed (0)". Report first, so that
    // reentrant call finds responded already set and no-ops.
    respond(null, "Response too large");
    xhr.abort();
    return true;
  }
  xhr.onreadystatechange = function() {
    if (xhr.readyState === XMLHttpRequest.LOADING) {
      rejectIfOversized();
      return;
    }
    if (xhr.readyState !== XMLHttpRequest.DONE) return;
    if (rejectIfOversized()) return;
    if (xhr.status >= 200 && xhr.status < 300) {
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
