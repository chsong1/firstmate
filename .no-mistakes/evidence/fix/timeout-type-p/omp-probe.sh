#!/usr/bin/env bash
# Run inside omp's bash tool. $1 = lib under test.
echo "type -a timeout:"; type -a timeout 2>&1 | head -3
echo "command -v timeout: $(command -v timeout)"
. "$1"
echo "mechanism=$(fm_timeout_mechanism)"
fm_run_timed 5 bash -c 'echo hello-stdout; exit 7'; echo "rc=$?"
s=$(date +%s); fm_run_timed 1 sleep 10; echo "bound rc=$? elapsed=$(( $(date +%s)-s ))s"
