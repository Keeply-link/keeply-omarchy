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
    lookupProcess.buf = "";
    lookupProcess.overflowed = false;
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
    id: lookupProcess
    property string buf: ""
    property bool overflowed: false

    stdout: SplitParser {
      // An empty splitMarker delivers whatever a single OS read returns,
      // rather than the default "\n" behavior of buffering an entire line
      // internally before onRead ever fires once. With the default, a
      // keyring value with no embedded newline would be fully buffered by
      // SplitParser itself — outside this file's control — before the
      // length check below ever got a chance to run, exactly the
      // post-materialization gap already fixed for API responses.
      splitMarker: ""
      onRead: function(value) {
        if (lookupProcess.overflowed) return;
        var next = lookupProcess.buf + value;
        if (next.length > root.maxTokenLength) {
          lookupProcess.overflowed = true;
          if (lookupProcess.running) lookupProcess.signal(15); // SIGTERM
          return;
        }
        lookupProcess.buf = next;
      }
    }
    onRunningChanged: {
      if (running) return;
      if (lookupProcess.overflowed) {
        root.token = "";
        root.ready = true;
        root.error("Stored credential is invalid");
      } else {
        var val = lookupProcess.buf.trim();
        if (val.length > 0) {
          root.token = val;
          root.tokenLoaded(root.token);
        } else {
          root.token = "";
        }
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
