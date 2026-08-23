import QtQuick
import Quickshell.Io

QtObject {
  id: root

  property string token: ""
  property bool ready: false

  readonly property string schema: "io.github.rolfkoenders.keeply"
  readonly property string key: "keeply_omarchy_token"

  signal tokenLoaded(string token)
  signal tokenCleared()
  signal error(string message)

  Component {
    id: lookupProcess
    Process {
      property string result: ""
      running: false
      command: ["secret-tool", "lookup", "application", root.schema]
      stdout: SplitParser {
        onRead: data => {
          if (data.length > 0) {
            root.token = data.trim();
            root.ready = true;
            root.tokenLoaded(root.token);
          } else {
            root.token = "";
            root.ready = true;
          }
        }
      }
      onRunningChanged: {
        if (!running && result.length === 0) {
          root.ready = true;
        }
      }
    }
  }

  Component {
    id: storeProcess
    Process {
      running: false
      command: ["secret-tool", "store", "--replace", "application", root.schema, "label", "Keeply for Omarchy"]
      onRunningChanged: {
        if (!running) {
          root.lookup();
        }
      }
    }
  }

  Component {
    id: clearProcess
    Process {
      running: false
      command: ["secret-tool", "clear", "application", root.schema]
      onRunningChanged: {
        if (!running) {
          root.token = "";
          root.tokenCleared();
        }
      }
    }
  }

  property var _lookupInstance: null
  property var _storeInstance: null
  property var _clearInstance: null

  function lookup() {
    if (_lookupInstance) {
      _lookupInstance.destroy();
    }
    _lookupInstance = lookupProcess.createObject(root);
    _lookupInstance.running = true;
  }

  function store(newToken) {
    if (_storeInstance) {
      _storeInstance.destroy();
    }
    _storeInstance = storeProcess.createObject(root);
    _storeInstance.stdin.write(newToken + "\n");
    _storeInstance.stdin.close();
    _storeInstance.running = true;
  }

  function clear() {
    if (_clearInstance) {
      _clearInstance.destroy();
    }
    _clearInstance = clearProcess.createObject(root);
    _clearInstance.running = true;
  }

  Component.onCompleted: {
    lookup();
  }
}
