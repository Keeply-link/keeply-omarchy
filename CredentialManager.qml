import QtQuick
import Quickshell.Io

QtObject {
  id: root

  property string token: ""
  property bool ready: false

  readonly property string schema: "io.github.rolfkoenders.keeply"

  // A real API key here is a short hex string; this rejects an absurdly
  // large keyring value instead of accepting it as a token, independent
  // of whatever wrote it there.
  readonly property int maxTokenLength: 4096

  signal tokenLoaded(string token)
  signal tokenCleared()
  signal error(string message)

  function lookup() {
    lookupProcess.command = ["secret-tool", "lookup", "application", root.schema];
    lookupProcess.running = true;
  }

  function store(newToken) {
    storeProcess.command = ["secret-tool", "store", "--label=Keeply for Omarchy", "application", root.schema];
    storeProcess.stdinEnabled = true;
    storeProcess.running = true;
  }

  function clear() {
    clearProcess.command = ["secret-tool", "clear", "application", root.schema];
    clearProcess.running = true;
  }

  property Process lookupProcess: Process {
    stdout: SplitParser {
      onRead: function(value) {
        var val = String(value || "").trim();
        if (val.length > root.maxTokenLength) {
          root.token = "";
          root.ready = true;
          root.error("Stored credential is invalid");
          return;
        }
        if (val.length > 0) {
          root.token = val;
          root.ready = true;
          root.tokenLoaded(root.token);
        } else {
          root.token = "";
          root.ready = true;
        }
      }
    }
    onRunningChanged: {
      if (!running) {
        root.ready = true;
      }
    }
  }

  property Process storeProcess: Process {
    stdinEnabled: true
    onStarted: {
      storeProcess.write(root._pendingToken + "\n");
      storeProcess.stdinEnabled = false;
    }
    onRunningChanged: {
      if (!running) {
        root.lookup();
      }
    }
  }

  property Process clearProcess: Process {
    onRunningChanged: {
      if (!running) {
        root.token = "";
        root.tokenCleared();
      }
    }
  }

  property string _pendingToken: ""

  Component.onCompleted: {
    lookup();
  }
}
