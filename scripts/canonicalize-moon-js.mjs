// Moon's Windows/Linux backends can print different decimal spellings for the
// same binary64 value. Normalize only decimal fractional/exponent literals.
// This is a lexical pass, not a JavaScript formatter: strings, comments, regexps,
// templates (including their expressions), integers and BigInts stay unchanged.
// A slash immediately following a closing brace is grammar-dependent (block
// versus object/function expression), so this unsupported form is rejected.
const identifierStart = /[$_\p{ID_Start}]/u;
const identifierPart = /[$_\u200c\u200d\p{ID_Continue}]/u;
const controlWords = new Set(["if", "while", "for", "with", "switch", "catch"]);
const expressionWords = new Set([
  "return", "throw", "case", "delete", "void", "typeof", "new", "in",
  "instanceof", "of", "yield", "await", "else", "do", "default", "break", "continue", "debugger",
]);

export function canonicalizeMoonJs(source) {
  if (typeof source !== "string") throw new TypeError("Moon JavaScript source must be a string");
  const edits = [];
  const fail = (message, offset) => { throw new SyntaxError(`${message} at offset ${offset}`); };
  const point = (at) => at < source.length ? String.fromCodePoint(source.codePointAt(at)) : "";
  const isPart = (at) => at < source.length && identifierPart.test(point(at));

  function identifierEnd(at) {
    while (at < source.length) {
      if (isPart(at)) at += point(at).length;
      else if (source[at] === "\\") {
        const escape = /^\\u(?:[\da-fA-F]{4}|\{[\da-fA-F]+\})/.exec(source.slice(at));
        if (!escape) fail("Unsupported identifier escape", at);
        at += escape[0].length;
      } else break;
    }
    return at;
  }

  function stringEnd(at) {
    const quote = source[at++];
    while (at < source.length) {
      const char = source[at++];
      if (char === quote) return at;
      if (char === "\\") {
        if (source[at] === "\r" && source[at + 1] === "\n") at++;
        at++;
      } else if (char === "\r" || char === "\n") fail("Unterminated string", at - 1);
    }
    fail("Unterminated string", at);
  }

  function regexpEnd(at) {
    const start = at++;
    let inClass = false;
    while (at < source.length) {
      const char = source[at++];
      if (char === "\r" || char === "\n") fail("Unterminated regular expression", start);
      if (char === "\\") at++;
      else if (char === "[") {
        if (inClass) fail("Unsupported nested regular expression class", start);
        inClass = true;
      }
      else if (char === "]") inClass = false;
      else if (char === "/" && !inClass) {
        const flags = identifierEnd(at);
        // Nested character classes in Unicode-set /v expressions need a
        // different lexer; reject them instead of guessing their boundary.
        if (source.slice(at, flags).includes("v")) fail("Unsupported regular expression v flag", start);
        return flags;
      }
    }
    fail("Unterminated regular expression", start);
  }

  function templateEnd(at) {
    const start = at++;
    while (at < source.length) {
      const char = source[at++];
      if (char === "\\") at++;
      else if (char === "`") return at;
      else if (char === "$" && source[at] === "{") at = scan(at + 1, true, false);
    }
    fail("Unterminated template", start);
  }

  function scan(at, templateExpression = false, rewrite = true) {
    const brackets = [];
    let expressionStart = true;
    let previous = "";
    let control = false;
    while (at < source.length) {
      const char = source[at];
      if (/\s/.test(char)) { at++; continue; }
      if (source.startsWith("//", at)) {
        while (at < source.length && !/[\r\n\u2028\u2029]/.test(source[at])) at++;
        continue;
      }
      if (source.startsWith("/*", at)) {
        const end = source.indexOf("*/", at + 2);
        if (end < 0) fail("Unterminated comment", at);
        at = end + 2;
        continue;
      }
      if (char === "'" || char === '"' || char === "`") {
        at = char === "`" ? templateEnd(at) : stringEnd(at);
        expressionStart = false;
        previous = "value";
        control = false;
        continue;
      }
      if (char === "/") {
        if (previous === "}") fail("Ambiguous slash after closing brace", at);
        if (expressionStart) { at = regexpEnd(at); expressionStart = false; previous = "value"; }
        else { at += source[at + 1] === "=" ? 2 : 1; expressionStart = true; previous = "/"; }
        control = false;
        continue;
      }
      if (/\d/.test(char) || char === "." && /\d/.test(source[at + 1] || "")) {
        const rest = source.slice(at);
        const match = /^(?:0[xX][\da-fA-F_]+n?|0[bB][01_]+n?|0[oO][0-7_]+n?|(?:\d[\d_]*(?:\.[\d_]*)?|\.[\d_]+)(?:[eE][+-]?[\d_]+)?n?)/.exec(rest);
        if (!match) fail("Unsupported numeric literal", at);
        const raw = match[0];
        if (rewrite && !/^0[xXbBoO]/.test(raw) && !/[n_]/.test(raw) && /[.eE]/.test(raw) && !/^0\d/.test(raw)) {
          const value = Number(raw);
          // Infinity is an identifier and can be shadowed; keep overflows.
          if (Number.isFinite(value)) {
            let canonical = value.toString();
            // 1.0.toString() and 1..toString() must not become 1.toString().
            if (/^\d+$/.test(canonical) && source[at + raw.length] === ".") canonical += ".0";
            if (canonical !== raw) edits.push([at, at + raw.length, canonical]);
          }
        }
        at += raw.length;
        expressionStart = false;
        previous = "value";
        control = false;
        continue;
      }
      if (identifierStart.test(point(at)) || char === "\\") {
        const end = identifierEnd(at);
        const word = source.slice(at, end);
        const property = previous === "." || previous === "?.";
        control = !property && (controlWords.has(word) || word === "await" && control && previous === "for");
        expressionStart = !property && expressionWords.has(word);
        previous = word;
        at = end;
        continue;
      }
      if (char === "(" || char === "[" || char === "{") {
        brackets.push({ char, control: char === "(" && control });
        expressionStart = true;
      } else if (char === ")" || char === "]" || char === "}") {
        if (char === "}" && brackets.length === 0 && templateExpression) return at + 1;
        const opening = brackets.pop();
        if (!opening || opening.char !== ({ ")": "(", "]": "[", "}": "{" })[char]) fail("Unbalanced delimiter", at);
        expressionStart = char === ")" && opening.control;
      } else {
        if (source.startsWith("...", at)) {
          at += 3;
          expressionStart = true;
          previous = "...";
          control = false;
          continue;
        }
        const pair = source.slice(at, at + 2);
        if (pair === "++" || pair === "--" || pair === "?.") {
          at += 2;
          if (pair === "?.") expressionStart = false;
          previous = pair;
          control = false;
          continue;
        }
        if (!";,:.?=+-*%&|^!~<>".includes(char)) fail("Unsupported JavaScript token", at);
        expressionStart = char !== ".";
      }
      previous = char;
      control = false;
      at++;
    }
    if (brackets.length || templateExpression) fail("Unterminated delimiter", at);
    return at;
  }

  scan(0);
  let result = "";
  let offset = 0;
  for (const [start, end, replacement] of edits) {
    result += source.slice(offset, start) + replacement;
    offset = end;
  }
  return result + source.slice(offset);
}
