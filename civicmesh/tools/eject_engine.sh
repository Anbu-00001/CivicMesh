#!/usr/bin/env sh
# Transpile the deterministic engine (engine/*.jac) and its eval harness to
# plain Python with `jac jac2py`, then run the eval with an interpreter that
# has no Jac installed.
#
#   cd civicmesh && sh tools/eject_engine.sh [out_dir] [python_without_jac]
#
# COLUMNS matters: jac2py prints through a terminal console that hard-wraps
# long lines at the terminal width, which turns long regex literals into a
# SyntaxError. A huge COLUMNS keeps every line intact.
set -eu
OUT="${1:-../civicmesh-engine-python}"
PY="${2:-}"
export COLUMNS=100000
mkdir -p "$OUT/engine" "$OUT/tests"
: > "$OUT/engine/__init__.py"
for f in engine/*.jac; do
  jac jac2py "$f" > "$OUT/engine/$(basename "$f" .jac).py"
done
jac jac2py tests/eval_engine.jac > "$OUT/tests/eval_engine.py"
if grep -rn "jaclang" "$OUT"; then
  echo "ejected code still imports jaclang" >&2
  exit 1
fi
echo "ejected to $OUT"
if [ -n "$PY" ]; then
  PYTHONPATH="$OUT" "$PY" "$OUT/tests/eval_engine.py"
fi
