#!/usr/bin/env bash
set -eu

if [ -f "$HOME/oss-cad-suite/environment" ]; then
    source "$HOME/oss-cad-suite/environment" >/dev/null
fi

simulator="${SIM:-icarus}"
if [ "${1:-}" = "--simulator" ]; then
    simulator="${2:-}"
    shift 2
fi
if [ "$simulator" != "icarus" ] && [ "$simulator" != "verilator" ]; then
    echo "usage: ./run_tests.sh [--simulator icarus|verilator]" >&2
    exit 2
fi
if [ "$#" -ne 0 ]; then
    echo "usage: ./run_tests.sh [--simulator icarus|verilator]" >&2
    exit 2
fi

project_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
workspace_dir=$(CDPATH= cd "$project_dir/../.." && pwd)
local_tools="$workspace_dir/work/iverilog-install/bin"

if [ -x "$local_tools/iverilog" ] && [ -x "$local_tools/vvp" ]; then
    PATH="$local_tools:$PATH"
    export PATH
fi

cd "$project_dir"
exec make test SIM="$simulator"
