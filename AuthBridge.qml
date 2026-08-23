import QtQuick
import Quickshell.Io

QtObject {
  id: root

  property bool running: false
  property string error: ""
  property string token: ""
  property string stdoutBuffer: ""
  property string stderrBuffer: ""
  property bool outputOverflowed: false

  // A token-exchange result or error message is at most a few hundred
  // bytes; this bounds what the shared shell process will hold onto
  // regardless of what the helper script actually does.
  readonly property int maxBufferBytes: 65536

  signal success(string token)
  signal failed(string message)

  function start() {
    if (running) return;
    running = true;
    error = "";
    token = "";
    stdoutBuffer = "";
    stderrBuffer = "";
    outputOverflowed = false;

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

  // Bounds what a runaway or hostile helper process can make this
  // long-lived shell process hold in memory, independent of whatever the
  // script itself does. Terminates the process on overflow rather than
  // just discarding further output, so it can't keep running indefinitely.
  function appendStdout(value) {
    if (root.outputOverflowed) return;
    var next = root.stdoutBuffer + value;
    if (next.length > root.maxBufferBytes) {
      root.outputOverflowed = true;
      root.stdoutBuffer = next.substring(0, root.maxBufferBytes);
      if (authProcess.running) authProcess.signal(15); // SIGTERM
      return;
    }
    root.stdoutBuffer = next;
  }

  function appendStderr(value) {
    if (root.outputOverflowed) return;
    var next = root.stderrBuffer + value;
    if (next.length > root.maxBufferBytes) {
      root.outputOverflowed = true;
      root.stderrBuffer = next.substring(0, root.maxBufferBytes);
      if (authProcess.running) authProcess.signal(15); // SIGTERM
      return;
    }
    root.stderrBuffer = next;
  }

  property Process authProcess: Process {
    stdout: SplitParser {
      onRead: function(value) {
        root.appendStdout(value);
      }
    }
    stderr: SplitParser {
      onRead: function(value) {
        root.appendStderr(value);
      }
    }
    onRunningChanged: {
      if (!running) {
        root.running = false;

        if (root.outputOverflowed) {
          root.error = "Auth helper produced unexpectedly large output";
          root.failed(root.error);
        } else if (root.stdoutBuffer.trim().length > 0) {
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
