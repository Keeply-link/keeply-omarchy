import QtQuick
import Quickshell.Io
import qs.Commons

import "Model.js" as Model

QtObject {
  id: root

  property bool isLoggedIn: false
  property bool loading: false
  property string errorMessage: ""
  property string user: ""
  property string query: ""
  property var recentBookmarks: []
  property var searchResults: []
  property var currentResults: []

  // Credential manager — declared as a property, not inline child
  property CredentialManager credentialManager: CredentialManager {
    id: credManager
    onTokenLoaded: function(token) {
      if (token.length > 0) {
        root.verifyAndConnect(token);
      }
    }
    onTokenCleared: {
      root.isLoggedIn = false;
      root.user = "";
      root.recentBookmarks = [];
      root.searchResults = [];
      root.currentResults = [];
    }
  }

  // API bridge — runs each request in a short-lived helper process
  // (bin/keeply-api) instead of QML's own XMLHttpRequest, since Qt
  // materializes the entire response into responseText inside this
  // long-lived shell process as it streams in, before any JS callback
  // can inspect or bound it. See ApiBridge.qml.
  property ApiBridge apiBridge: ApiBridge {
    id: api
  }

  // Auth bridge for OAuth flow
  property AuthBridge authBridge: AuthBridge {
    id: bridge
    onSuccess: function(token) {
      credManager._pendingToken = token;
      credManager.store(token);
      root.verifyAndConnect(token);
    }
    onFailed: function(message) {
      root.loading = false;
      root.errorMessage = message;
    }
  }

  function login() {
    root.loading = true;
    root.errorMessage = "";
    bridge.start();
  }

  function logout() {
    credManager.clear();
  }

  function verifyAndConnect(token) {
    root.loading = true;
    api.verifyToken(token, function(result, err) {
      if (result) {
        root.isLoggedIn = true;
        root.user = result.email || result.name || "";
        root.loading = false;
        root.fetchRecent();
      } else {
        root.isLoggedIn = false;
        root.user = "";
        root.loading = false;
        credManager.clear();
      }
    });
  }

  function fetchRecent() {
    if (!root.isLoggedIn) return;
    var token = credManager.token;
    root.loading = true;
    api.fetchBookmarks(token, 1, 20, "date-desc", function(result, err) {
      root.loading = false;
      if (result && result.data) {
        var rows = [];
        for (var i = 0; i < result.data.length; i++) {
          rows.push(Model.bookmarkToRow(result.data[i]));
        }
        root.recentBookmarks = rows;
        if (root.query.length === 0) {
          root.currentResults = rows;
        }
      }
    });
  }

  function search(q) {
    if (!root.isLoggedIn) return;
    root.query = q;

    if (q.length === 0) {
      root.searchResults = [];
      root.currentResults = root.recentBookmarks;
      return;
    }

    var token = credManager.token;
    root.loading = true;
    api.searchBookmarks(token, q, 1, 30, function(result, err) {
      // A faster keystroke may have already superseded this request.
      if (root.query !== q) return;
      root.loading = false;
      if (result && result.hits) {
        var rows = [];
        for (var i = 0; i < result.hits.length; i++) {
          rows.push(Model.bookmarkToRow(result.hits[i]));
        }
        root.searchResults = rows;
        root.currentResults = rows;
      } else {
        root.searchResults = [];
        root.currentResults = [];
      }
    });
  }

  function openBookmark(url) {
    // Bookmark URLs come from the server, not user input typed here, but
    // never hand an arbitrary scheme to the platform's URL handler — only
    // plain web links should ever come out of a bookmark manager.
    var scheme = String(url || "").match(/^([a-zA-Z][a-zA-Z0-9+.-]*):/);
    if (!scheme || (scheme[1].toLowerCase() !== "http" && scheme[1].toLowerCase() !== "https")) {
      root.errorMessage = "Refused to open a non-web link.";
      return;
    }
    Qt.openUrlExternally(url);
  }

  Component.onCompleted: {
    credManager.lookup();
  }
}
