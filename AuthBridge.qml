import QtQuick
import Quickshell.Io

QtObject {
  id: root

  property bool running: false
  property string error: ""
  property string token: ""
  property string stdoutBuffer: ""
  property string stderrBuffer: ""

  signal success(string token)
  signal failed(string message)

  function start() {
    if (running) return;
    running = true;
    error = "";
    token = "";
    stdoutBuffer = "";
    stderrBuffer = "";

    try {
      var scriptPath = String(Qt.resolvedUrl("bin/keeply-auth"));
      if (scriptPath.startsWith("file://")) {
        scriptPath = scriptPath.substring(7);
      }

      authProcess.command = ["python3", scriptPath];
      authProcess.running = true;
    } catch (e) {
      running = false;
      error = "Could not start auth helper: " + e;
      failed(error);
    }
  }

  function cancel() {
    if (authProcess.running) {
      authProcess.signal(2); // SIGINT
    }
    running = false;
    error = "Cancelled";
    failed(error);
  }

  property Process authProcess: Process {
    stdout: SplitParser {
      onRead: function(value) {
        root.stdoutBuffer += value;
      }
    }
    stderr: SplitParser {
      onRead: function(value) {
        root.stderrBuffer += value;
      }
    }
    onRunningChanged: {
      if (!running) {
        root.running = false;

        if (root.stdoutBuffer.trim().length > 0) {
          try {
            var result = JSON.parse(root.stdoutBuffer.trim());
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
        } else if (root.stderrBuffer.trim().length > 0) {
          root.error = root.stderrBuffer.trim();
          root.failed(root.error);
        } else {
          root.error = "Auth helper exited unexpectedly";
          root.failed(root.error);
        }
      }
    }
  }
}
