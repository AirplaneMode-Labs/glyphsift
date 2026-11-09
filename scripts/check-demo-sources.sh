#!/usr/bin/env bash
# Grep gate for the demo sources: every report-derived string and every pasted character must reach
# the page through textContent or createTextNode, never as markup. Fails on innerHTML, outerHTML,
# insertAdjacentHTML, document.write, eval or new Function in demo/*.js, and on any inline script,
# inline style or inline event handler in demo/index.html. Run by scripts/build-demo.sh and CI.
set -euo pipefail
cd "$(dirname "$0")/.."

bad=0
if grep -nE 'innerHTML|outerHTML|insertAdjacentHTML|document\.write|[^A-Za-z]eval\(|new Function' demo/*.js; then
  echo "error: demo/*.js uses a markup-injecting or code-evaluating API; use textContent / createTextNode" >&2
  bad=1
fi
if grep -nEi '<script[^>]*>[^<]|<style|style="| on[a-z]+="' demo/index.html | grep -v 'src="'; then
  echo "error: demo/index.html has inline script, style or event handler (the CSP forbids them)" >&2
  bad=1
fi
[ "$bad" -eq 0 ] || exit 1
echo "demo sources: no innerHTML, outerHTML, insertAdjacentHTML, eval or inline code"
