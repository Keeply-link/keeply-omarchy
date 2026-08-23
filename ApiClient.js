.pragma library

const API_BASE = "https://api.keeply.tools";

function createRequest(method, path, token, body) {
  const url = API_BASE + path;
  const xhr = new XMLHttpRequest();
  xhr.open(method, url, false);
  xhr.setRequestHeader("Authorization", "ApiKey " + token);
  xhr.setRequestHeader("Content-Type", "application/json");
  if (body) {
    xhr.send(JSON.stringify(body));
  } else {
    xhr.send();
  }
  return xhr;
}

function verifyToken(token) {
  const xhr = createRequest("GET", "/users/me", token);
  if (xhr.status === 200) {
    return JSON.parse(xhr.responseText);
  }
  return null;
}

function searchBookmarks(token, query, page, limit) {
  page = page || 1;
  limit = limit || 30;
  const params = "?q=" + encodeURIComponent(query) + "&page=" + page + "&limit=" + limit;
  const xhr = createRequest("GET", "/search" + params, token);
  if (xhr.status === 200) {
    return JSON.parse(xhr.responseText);
  }
  return null;
}

function fetchBookmarks(token, page, limit, sort) {
  page = page || 1;
  limit = limit || 30;
  sort = sort || "date-desc";
  const params = "?page=" + page + "&limit=" + limit + "&sort=" + sort;
  const xhr = createRequest("GET", "/bookmarks" + params, token);
  if (xhr.status === 200) {
    return JSON.parse(xhr.responseText);
  }
  return null;
}

function fetchFolders(token) {
  const xhr = createRequest("GET", "/folders", token);
  if (xhr.status === 200) {
    return JSON.parse(xhr.responseText);
  }
  return [];
}

function fetchTags(token) {
  const xhr = createRequest("GET", "/tags", token);
  if (xhr.status === 200) {
    return JSON.parse(xhr.responseText);
  }
  return [];
}

function fetchSidebarData(token) {
  const xhr = createRequest("GET", "/bookmarks/sidebar-data", token);
  if (xhr.status === 200) {
    return JSON.parse(xhr.responseText);
  }
  return null;
}
