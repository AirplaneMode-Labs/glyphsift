#!/usr/bin/env bash
# Grep gate for the demo sources: every report-derived string, every file's text and every pasted
# character must reach the page through textContent or createTextNode, never as markup. Fails on
# innerHTML, outerHTML, insertAdjacentHTML, document.write, eval or new Function in demo/*.js, on any
# style attribute set from script (setAttribute("style"), .style, cssText), and on any inline script,
# inline style attribute or inline event handler in demo/index.html. Run by scripts/build-demo.sh and CI.
set -euo pipefail
cd "$(dirname "$0")/.."

bad=0
if grep -nE 'innerHTML|outerHTML|insertAdjacentHTML|document\.write|[^A-Za-z]eval\(|new Function' demo/*.js; then
  echo "error: demo/*.js uses a markup-injecting or code-evaluating API; use textContent / createTextNode" >&2
  bad=1
fi
if grep -nE 'setAttribute\(\s*["'"'"']style|\.style\b|cssText|\sstyle\s*=' demo/*.js; then
  echo "error: demo/*.js sets a style attribute; the CSP forbids inline styles, use the fixed class names in styles.css" >&2
  bad=1
fi
if grep -nEi '<script[^>]*>[^<]|<style|style="| on[a-z]+="' demo/index.html | grep -v 'src="'; then
  echo "error: demo/index.html has inline script, style or event handler (the CSP forbids them)" >&2
  bad=1
fi
[ "$bad" -eq 0 ] || exit 1
echo "demo sources: no innerHTML, outerHTML, insertAdjacentHTML, document.write, eval, style attribute or inline code"
