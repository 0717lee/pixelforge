#!/usr/bin/env node
import assert from "node:assert/strict";
import { canonicalizeMoonJs } from "./canonicalize-moon-js.mjs";

// Actual Windows/Linux Moon output: different text, identical binary64 values.
const windows = "const x = [0.21237636070506746, 0.086563782369209585];";
const linux = "const x = [0.212376360705067463, 0.0865637823692095854];";
assert.equal(canonicalizeMoonJs(windows), canonicalizeMoonJs(linux));
assert.equal(canonicalizeMoonJs("const x = [1.000, 1e+00, .5000, 1e-7];"), "const x = [1, 1, 0.5, 1e-7];");

const preserved = [
  "const integers = [9007199254740993, 0xff, 0XFE, 0b101, 0o77, 1_000, 0xFFn, 12345678901234567890n];",
  'const text = "0.212376360705067463 \\\" .5000"; // 1.000\n/* 1e+00 */',
  "const r = /[0-9.]+1.000\\/1e+00/gi;",
  "if (ok) /1.000/.test(s); while (ok) /1e+00/.test(s);",
  "const spread = [.../1.000/.source]; for (const x of /1.000/.source) /1.000/.test(x);",
  "async function f() { for await (const x of xs) /1.000/.test(x); } export default /1.000/;",
  'const template = `1.000 ${"a`1.000"} ${/1.000/.test(s)} ${`nested ${1.000}`} \\` tail`;',
  "const overflow = 1e999; const separated = 1_000.000_1;",
];
for (const source of preserved) assert.equal(canonicalizeMoonJs(source), source);

assert.equal(canonicalizeMoonJs("obj.return / 1.000; obj.if(x) / 2.000; (x + 1.000) / 2.000;"), "obj.return / 1; obj.if(x) / 2; (x + 1) / 2;");
assert.equal(canonicalizeMoonJs("const π1 = 1.000; const x\\u0031 = 2.000;"), "const π1 = 1; const x\\u0031 = 2;");
assert.equal(canonicalizeMoonJs("const r = /1.000/; const x = 1.000;"), "const r = /1.000/; const x = 1;");
assert.equal(canonicalizeMoonJs("const t = `raw ${1.000}`; const x = 2.000;"), "const t = `raw ${1.000}`; const x = 2;");

for (const expression of ["-0.000", "-1e-999", "1e999", "1.0.toString()", "1..toString()", "1e0.toString()", "1.0?.toString()", "2.50 / 1.25", "0.212376360705067463"]) {
  const source = `return (${expression});`;
  const canonical = canonicalizeMoonJs(source);
  assert.ok(Object.is(Function(source)(), Function(canonical)()), `${expression} changed value`);
  assert.equal(canonicalizeMoonJs(canonical), canonical, `${expression} is not idempotent`);
}

assert.throws(() => canonicalizeMoonJs("if (ok) {} /1.000/.test(s);"), /Ambiguous slash/);
assert.throws(() => canonicalizeMoonJs("const r = /[a&&b]/v;"), /Unsupported regular expression v flag/);
assert.throws(() => canonicalizeMoonJs("const r = /[[a]/1.000]/v;"), /Unsupported nested regular expression class/);
assert.throws(() => canonicalizeMoonJs('const x = "unterminated'), /Unterminated string/);
assert.throws(() => canonicalizeMoonJs("const x = `unterminated ${1.0}"), /Unterminated template/);
console.log("OK Moon JS decimal canonicalization: platform values, lexical boundaries, templates, integers/BigInt, negative zero and member syntax");
