#!/usr/bin/env node
// Tests for ApiClient.js's response-size capping, run against the real
// file (not a duplicated copy) via a mocked XMLHttpRequest, since QML's
// XHR isn't available outside the shell but the request() logic itself
// has no other QML dependency.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const SOURCE_PATH = path.join(__dirname, "..", "ApiClient.js");

function loadApiClient(XMLHttpRequestMock) {
  const source = fs
    .readFileSync(SOURCE_PATH, "utf8")
    .replace(/^\.pragma library\s*/m, ""); // not valid outside QML

  const sandbox = { XMLHttpRequest: XMLHttpRequestMock, console };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename: "ApiClient.js" });
  return sandbox;
}

// A controllable fake XHR: the test drives state transitions manually by
// calling triggerHeaders()/triggerDone() rather than doing real network IO.
function makeFakeXHRClass(responseHeaders) {
  class FakeXHR {
    constructor() {
      this.readyState = 0;
      this.status = 0;
      this.responseText = "";
      this.aborted = false;
      this._headers = responseHeaders || {};
    }
    open() {}
    setRequestHeader() {}
    send() {}
    abort() {
      this.aborted = true;
      this.readyState = FakeXHR.DONE;
      this.status = 0;
      if (this.onreadystatechange) this.onreadystatechange();
    }
    getResponseHeader(name) {
      return this._headers[name] || null;
    }
    triggerHeaders() {
      this.readyState = FakeXHR.HEADERS_RECEIVED;
      if (this.onreadystatechange) this.onreadystatechange();
    }
    triggerLoading(responseTextSoFar) {
      this.readyState = FakeXHR.LOADING;
      this.status = 200;
      this.responseText = responseTextSoFar;
      if (this.onreadystatechange) this.onreadystatechange();
    }
    triggerDone(status, responseText) {
      this.readyState = FakeXHR.DONE;
      this.status = status;
      this.responseText = responseText;
      if (this.onreadystatechange) this.onreadystatechange();
    }
  }
  FakeXHR.UNSENT = 0;
  FakeXHR.OPENED = 1;
  FakeXHR.HEADERS_RECEIVED = 2;
  FakeXHR.LOADING = 3;
  FakeXHR.DONE = 4;
  return FakeXHR;
}

let failures = 0;

function check(name, condition) {
  if (condition) {
    console.log("PASS " + name);
  } else {
    console.log("FAIL " + name);
    failures++;
  }
}

// Tests need to drive the exact XHR instance request() constructs
// internally, so instances register themselves on the class as they're
// created.
function makeTrackedFakeXHRClass(responseHeaders) {
  const Base = makeFakeXHRClass(responseHeaders);
  class Tracked extends Base {
    constructor() {
      super();
      Tracked.instances.push(this);
    }
  }
  Tracked.instances = [];
  Tracked.UNSENT = Base.UNSENT;
  Tracked.OPENED = Base.OPENED;
  Tracked.HEADERS_RECEIVED = Base.HEADERS_RECEIVED;
  Tracked.LOADING = Base.LOADING;
  Tracked.DONE = Base.DONE;
  return Tracked;
}

function run_success_parses_json() {
  const FakeXHR = makeTrackedFakeXHRClass();
  const { request } = loadApiClient(FakeXHR);
  let calls = [];
  request("GET", "/bookmarks", "tok", null, function(result, error) {
    calls.push([result, error]);
  });
  const xhr = FakeXHR.instances[0];
  xhr.triggerDone(200, JSON.stringify({ data: [1, 2, 3] }));

  check("success passes parsed JSON with no error", calls.length === 1 && calls[0][1] === null && calls[0][0].data.length === 3);
}

function run_non_2xx_status_reports_error() {
  const FakeXHR = makeTrackedFakeXHRClass();
  const { request } = loadApiClient(FakeXHR);
  let calls = [];
  request("GET", "/bookmarks", "tok", null, function(result, error) {
    calls.push([result, error]);
  });
  const xhr = FakeXHR.instances[0];
  xhr.triggerDone(404, "");

  check("non-2xx status reports an error, not a crash", calls.length === 1 && calls[0][0] === null && /404/.test(calls[0][1]));
}

function run_invalid_json_reports_error() {
  const FakeXHR = makeTrackedFakeXHRClass();
  const { request } = loadApiClient(FakeXHR);
  let calls = [];
  request("GET", "/bookmarks", "tok", null, function(result, error) {
    calls.push([result, error]);
  });
  const xhr = FakeXHR.instances[0];
  xhr.triggerDone(200, "{not valid json");

  check("invalid JSON reports an error instead of throwing", calls.length === 1 && calls[0][0] === null && calls[0][1] === "Invalid response from server");
}

function run_headers_received_never_aborts() {
  // Deliberately NOT checking Content-Length at HEADERS_RECEIVED: verified
  // empirically against a real Qt/QML runtime that calling xhr.abort() that
  // early (before any body has buffered into responseText) reproducibly
  // segfaults Qt's QNetworkReply internals. Only actual buffered bytes
  // (checked on LOADING) may trigger an abort — a large Content-Length
  // header alone must never do so.
  const tooLarge = String(6 * 1024 * 1024); // over the 5 MiB cap
  const FakeXHR = makeTrackedFakeXHRClass({ "Content-Length": tooLarge });
  const { request } = loadApiClient(FakeXHR);
  let calls = [];
  request("GET", "/bookmarks", "tok", null, function(result, error) {
    calls.push([result, error]);
  });
  const xhr = FakeXHR.instances[0];
  xhr.triggerHeaders();

  check("a large Content-Length header alone never triggers abort", xhr.aborted === false);
  check("no callback fires from HEADERS_RECEIVED alone", calls.length === 0);
}

function run_abort_does_not_double_invoke_callback() {
  const FakeXHR = makeTrackedFakeXHRClass({});
  const { request } = loadApiClient(FakeXHR);
  let calls = [];
  request("GET", "/bookmarks", "tok", null, function(result, error) {
    calls.push([result, error]);
  });
  const xhr = FakeXHR.instances[0];
  const hugeBody = "x".repeat(6 * 1024 * 1024);
  xhr.triggerLoading(hugeBody); // this internally calls abort(), which itself fires onreadystatechange again at DONE

  check("callback fires exactly once even though abort() re-triggers onreadystatechange", calls.length === 1);
}

function run_oversized_body_without_content_length_header() {
  // Simulates a response that completes in a single read with no prior
  // LOADING event and no Content-Length header (e.g. chunked encoding on
  // a very fast connection) — the DONE-time check is the last resort for
  // this edge case, since there was no earlier chance to catch it.
  const FakeXHR = makeTrackedFakeXHRClass({});
  const { request } = loadApiClient(FakeXHR);
  let calls = [];
  request("GET", "/bookmarks", "tok", null, function(result, error) {
    calls.push([result, error]);
  });
  const xhr = FakeXHR.instances[0];
  const hugeBody = "x".repeat(5 * 1024 * 1024 + 1);
  xhr.triggerDone(200, hugeBody);

  check("oversized body with no Content-Length is still rejected", calls.length === 1 && calls[0][0] === null && calls[0][1] === "Response too large");
}

function run_incremental_loading_aborts_before_full_download() {
  // The realistic attack shape: no Content-Length, response streams in
  // over many chunks. Must be caught as soon as the cap is crossed, not
  // only once the whole thing has already arrived.
  const FakeXHR = makeTrackedFakeXHRClass({});
  const { request } = loadApiClient(FakeXHR);
  let calls = [];
  request("GET", "/bookmarks", "tok", null, function(result, error) {
    calls.push([result, error]);
  });
  const xhr = FakeXHR.instances[0];

  const chunkSize = 1024 * 1024; // 1 MiB per simulated chunk, cap is 5 MiB
  let soFar = "";
  let abortedAtLength = null;
  for (let i = 0; i < 20 && !xhr.aborted; i++) {
    soFar += "x".repeat(chunkSize);
    xhr.triggerLoading(soFar);
    if (xhr.aborted && abortedAtLength === null) abortedAtLength = soFar.length;
  }

  check("incremental growth is aborted once the cap is crossed", xhr.aborted === true);
  check(
    "abort happens well before the full 20 MiB would have arrived",
    abortedAtLength !== null && abortedAtLength <= 6 * 1024 * 1024,
  );
  check("reports 'Response too large' exactly once for the incremental case", calls.length === 1 && calls[0][0] === null && calls[0][1] === "Response too large");
}

run_success_parses_json();
run_non_2xx_status_reports_error();
run_invalid_json_reports_error();
run_headers_received_never_aborts();
run_abort_does_not_double_invoke_callback();
run_oversized_body_without_content_length_header();
run_incremental_loading_aborts_before_full_download();

if (failures > 0) {
  console.log("\n" + failures + " test(s) FAILED");
  process.exit(1);
} else {
  console.log("\nAll tests passed!");
}
