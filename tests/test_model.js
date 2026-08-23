#!/usr/bin/env node
// Tests for Model.js's result-shaping/capping logic, run against the real
// file (not a duplicated copy) via Node's vm module, since Model.js has no
// QML dependency beyond the .pragma library directive.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const SOURCE_PATH = path.join(__dirname, "..", "Model.js");

function loadModel() {
  const source = fs
    .readFileSync(SOURCE_PATH, "utf8")
    .replace(/^\.pragma library\s*/m, ""); // not valid outside QML

  const sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename: "Model.js" });
  return sandbox;
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

function run_cap_string_leaves_short_values_untouched() {
  const Model = loadModel();
  check("capString leaves a short value untouched", Model.capString("hello", 100) === "hello");
}

function run_cap_string_truncates_long_values() {
  const Model = loadModel();
  const result = Model.capString("x".repeat(200), 100);
  check("capString truncates to exactly the limit", result.length === 100);
}

function run_cap_string_handles_missing_values() {
  const Model = loadModel();
  check("capString treats null as empty string", Model.capString(null, 10) === "");
  check("capString treats undefined as empty string", Model.capString(undefined, 10) === "");
}

function run_bookmark_to_row_caps_title() {
  const Model = loadModel();
  const row = Model.bookmarkToRow({ title: "x".repeat(1000), url: "https://example.com" });
  check("title is capped at MAX_TITLE_LENGTH", row.title.length === Model.MAX_TITLE_LENGTH);
}

function run_bookmark_to_row_caps_url() {
  const Model = loadModel();
  const hugeUrl = "https://example.com/" + "x".repeat(5000);
  const row = Model.bookmarkToRow({ title: "t", url: hugeUrl });
  check("url is capped at MAX_URL_LENGTH", row.url.length === Model.MAX_URL_LENGTH);
}

function run_bookmark_to_row_caps_description_and_note() {
  const Model = loadModel();
  const row = Model.bookmarkToRow({
    title: "t",
    url: "https://example.com",
    description: "d".repeat(5000),
    note: "n".repeat(5000),
  });
  check("description is capped", row.description.length === Model.MAX_TEXT_FIELD_LENGTH);
  check("note is capped", row.note.length === Model.MAX_TEXT_FIELD_LENGTH);
}

function run_bookmark_to_row_caps_folder_name() {
  const Model = loadModel();
  const row = Model.bookmarkToRow({
    title: "t",
    url: "https://example.com",
    folder: { name: "f".repeat(1000) },
  });
  check("folder name is capped", row.folderName.length === Model.MAX_FOLDER_NAME_LENGTH);
}

function run_bookmark_to_row_caps_tag_count() {
  const Model = loadModel();
  const tags = [];
  for (let i = 0; i < 500; i++) tags.push({ name: "tag" + i });
  const row = Model.bookmarkToRow({ title: "t", url: "https://example.com", tags: tags });
  check("tag count is capped at MAX_TAGS_PER_BOOKMARK", row.tagNames.length === Model.MAX_TAGS_PER_BOOKMARK);
}

function run_bookmark_to_row_caps_each_tag_name_length() {
  const Model = loadModel();
  const row = Model.bookmarkToRow({
    title: "t",
    url: "https://example.com",
    tags: [{ name: "t".repeat(1000) }],
  });
  check("each tag name is length-capped", row.tagNames[0].length === Model.MAX_TAG_NAME_LENGTH);
}

function run_bookmark_to_row_handles_nested_tag_shape() {
  const Model = loadModel();
  const row = Model.bookmarkToRow({
    title: "t",
    url: "https://example.com",
    tags: [{ tag: { name: "nested" } }],
  });
  check("nested {tag: {name}} shape is still extracted", row.tagNames[0] === "nested");
}

function run_bookmarks_to_rows_caps_result_count() {
  const Model = loadModel();
  const bookmarks = [];
  for (let i = 0; i < 100000; i++) bookmarks.push({ title: "t" + i, url: "https://example.com" });
  const rows = Model.bookmarksToRows(bookmarks);
  check(
    "a huge array is capped at MAX_RESULTS regardless of what the server sent",
    rows.length === Model.MAX_RESULTS,
  );
}

function run_bookmarks_to_rows_handles_missing_input() {
  const Model = loadModel();
  check("bookmarksToRows(null) returns an empty array", Model.bookmarksToRows(null).length === 0);
  check("bookmarksToRows(undefined) returns an empty array", Model.bookmarksToRows(undefined).length === 0);
}

function run_bookmarks_to_rows_preserves_order_under_the_cap() {
  const Model = loadModel();
  const bookmarks = [{ title: "first", url: "https://a.com" }, { title: "second", url: "https://b.com" }];
  const rows = Model.bookmarksToRows(bookmarks);
  check("row order is preserved", rows[0].title === "first" && rows[1].title === "second");
}

run_cap_string_leaves_short_values_untouched();
run_cap_string_truncates_long_values();
run_cap_string_handles_missing_values();
run_bookmark_to_row_caps_title();
run_bookmark_to_row_caps_url();
run_bookmark_to_row_caps_description_and_note();
run_bookmark_to_row_caps_folder_name();
run_bookmark_to_row_caps_tag_count();
run_bookmark_to_row_caps_each_tag_name_length();
run_bookmark_to_row_handles_nested_tag_shape();
run_bookmarks_to_rows_caps_result_count();
run_bookmarks_to_rows_handles_missing_input();
run_bookmarks_to_rows_preserves_order_under_the_cap();

if (failures > 0) {
  console.log("\n" + failures + " test(s) FAILED");
  process.exit(1);
} else {
  console.log("\nAll tests passed!");
}
