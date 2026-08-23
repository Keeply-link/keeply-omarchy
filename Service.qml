import QtQuick
import Quickshell.Io
import qs.Commons

import "ApiClient.js" as Api
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

  readonly property string settingsPath: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/keeply-omarchy/config.json"

  // Credential manager
  property var credentialManager: CredentialManager {
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

  // Auth bridge for OAuth flow
  property var authBridge: AuthBridge {
    id: bridge
    onSuccess: function(token) {
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
    var result = Api.verifyToken(token);
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
  }

  function fetchRecent() {
    if (!root.isLoggedIn) return;
    var token = credManager.token;
    var result = Api.fetchBookmarks(token, 1, 20, "date-desc");
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
    var result = Api.searchBookmarks(token, q, 1, 30);
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
  }

  function openBookmark(url) {
    Qt.openUrlExternally(url);
  }

  function init() {
    credManager.lookup();
  }

  Component.onCompleted: {
    init();
  }
}
