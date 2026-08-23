import QtQuick
import Quickshell.Io

QtObject {
  id: root

  // Every response is a bounded list of bookmarks/folders/tags or a single
  // small object; 5 MiB matches the cap keeply-api itself enforces during
  // the actual socket read. This is defense in depth, not the real bound:
  // it only guards against the helper process itself misbehaving, since
  // keeply-api has already capped what it read from the network before
  // any of this ever reaches stdout.
  readonly property int maxStdoutBytes: 5 * 1024 * 1024
  readonly property int maxStderrBytes: 65536

  property Component _processComponent: Component {
    Process {
      id: proc
      property var callback: null
      property string requestPayload: ""
      property string stdoutBuf: ""
      property string stderrBuf: ""
      property bool overflowed: false

      stdinEnabled: true

      // running becomes true only once the OS process has actually
      // started (it's async — setting the running property doesn't take
      // effect synchronously), so writing stdin right after setting
      // running = true is a silent no-op and the helper hangs forever on
      // an empty stdin read. started() fires once the process is
      // actually ready to receive it.
      onStarted: {
        proc.write(proc.requestPayload);
      }

      stdout: SplitParser {
        // An empty splitMarker delivers whatever a single OS read returns,
        // instead of the default "\n" behavior of buffering an entire line
        // internally before onRead ever fires once. The accumulation below
        // already caps across multiple calls, so this only changes how
        // early each chunk is checked, catching a helper that emits one
        // huge unbroken line before the default delimiter search ever would.
        splitMarker: ""
        onRead: function(value) {
          if (proc.overflowed) return;
          var next = proc.stdoutBuf + value;
          if (next.length > root.maxStdoutBytes) {
            proc.overflowed = true;
            proc.stdoutBuf = next.substring(0, root.maxStdoutBytes);
            if (proc.running) proc.signal(15); // SIGTERM
            return;
          }
          proc.stdoutBuf = next;
        }
      }
      stderr: SplitParser {
        splitMarker: ""
        onRead: function(value) {
          if (proc.overflowed) return;
          var next = proc.stderrBuf + value;
          if (next.length > root.maxStderrBytes) {
            proc.overflowed = true;
            proc.stderrBuf = next.substring(0, root.maxStderrBytes);
            if (proc.running) proc.signal(15); // SIGTERM
            return;
          }
          proc.stderrBuf = next;
        }
      }

      onRunningChanged: {
        if (running) return;
        var cb = proc.callback;
        var stdoutBuf = proc.stdoutBuf;
        var stderrBuf = proc.stderrBuf;
        var overflowed = proc.overflowed;
        proc.destroy();
        if (!cb) return;

        if (overflowed) {
          cb(null, "Response too large");
        } else if (stdoutBuf.trim().length > 0) {
          try {
            cb(JSON.parse(stdoutBuf.trim()), null);
          } catch (e) {
            cb(null, "Invalid response from server");
          }
        } else if (stderrBuf.trim().length > 0) {
          var err = stderrBuf.trim();
          if (err.indexOf("http_status:") === 0) {
            cb(null, "Request failed (" + err.substring("http_status:".length) + ")");
          } else {
            cb(null, err);
          }
        } else {
          cb(null, "API helper exited unexpectedly");
        }
      }
    }
  }

  function request(method, path, token, body, callback) {
    try {
      var scriptPath = String(Qt.resolvedUrl("bin/keeply-api"));
      if (scriptPath.startsWith("file://")) {
        scriptPath = scriptPath.substring(7);
      }

      var proc = root._processComponent.createObject(root, {
        callback: callback,
        command: ["python3", scriptPath],
        requestPayload: JSON.stringify({ method: method, path: path, token: token, body: body || null }) + "\n",
      });
      proc.running = true;
    } catch (e) {
      callback(null, "Could not start API helper: " + e);
    }
  }

  function verifyToken(token, callback) {
    root.request("GET", "/users/me", token, null, callback);
  }

  function searchBookmarks(token, query, page, limit, callback) {
    page = page || 1;
    limit = limit || 30;
    const params = "?q=" + encodeURIComponent(query) + "&page=" + page + "&limit=" + limit;
    root.request("GET", "/search" + params, token, null, callback);
  }

  function fetchBookmarks(token, page, limit, sort, callback) {
    page = page || 1;
    limit = limit || 30;
    sort = sort || "date-desc";
    const params = "?page=" + page + "&limit=" + limit + "&sort=" + sort;
    root.request("GET", "/bookmarks" + params, token, null, callback);
  }

  function fetchFolders(token, callback) {
    root.request("GET", "/folders", token, null, callback);
  }

  function fetchTags(token, callback) {
    root.request("GET", "/tags", token, null, callback);
  }

  function fetchSidebarData(token, callback) {
    root.request("GET", "/bookmarks/sidebar-data", token, null, callback);
  }
}
