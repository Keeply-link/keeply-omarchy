import QtQuick
import Quickshell.Io

QtObject {
  id: root

  property bool running: false
  property string error: ""
  property string token: ""

  signal success(string token)
  signal failed(string message)

  property var _process: null

  function start() {
    if (running) return;
    running = true;
    error = "";
    token = "";

    var scriptPath = Qt.resolvedUrl("bin/keeply-auth");
    if (scriptPath.startsWith("file://")) {
      scriptPath = scriptPath.substring(7);
    }

    _process = processComponent.createObject(root, {
      command: ["python3", scriptPath]
    });
    _process.running = true;
  }

  function cancel() {
    if (_process) {
      _process.signal(2); // SIGINT
    }
    running = false;
    error = "Cancelled";
    failed(error);
  }

  property Component processComponent: Component {
    Process {
      id: proc
      property string stdoutBuffer: ""
      property string stderrBuffer: ""

      stdout: SplitParser {
        onRead: data => {
          proc.stdoutBuffer += data;
        }
      }

      stderr: SplitParser {
        onRead: data => {
          proc.stderrBuffer += data;
        }
      }

      onRunningChanged: {
        if (!running) {
          root.running = false;

          if (stdoutBuffer.trim().length > 0) {
            try {
              var result = JSON.parse(stdoutBuffer.trim());
              if (result.accessToken) {
                root.token = result.accessToken;
                root.success(root.token);
              } else if (result.error) {
                root.error = result.error;
                root.failed(root.error);
              }
            } catch (e) {
              root.error = "Invalid response from auth helper";
              root.failed(root.error);
            }
          } else if (stderrBuffer.trim().length > 0) {
            root.error = stderrBuffer.trim();
            root.failed(root.error);
          } else {
            root.error = "Auth helper exited unexpectedly";
            root.failed(root.error);
          }

          proc.destroy();
          _process = null;
        }
      }
    }
  }
}
