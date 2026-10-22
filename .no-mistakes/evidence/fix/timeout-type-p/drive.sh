#!/usr/bin/env bash
# usage: drive.sh <lib>
lib=$1
echo "== lib: $lib"
echo "-- S1 shadowed timeout/gtimeout functions: stdout + exit 7 preserved"
out=$( unset FM_TIMEOUT_MECHANISM_OVERRIDE; timeout(){ echo shadowed-timeout; return 0; }; gtimeout(){ echo shadowed-gtimeout; return 0; }; . "$lib"; echo "mechanism=$(fm_timeout_mechanism)" >&2; fm_run_timed 5 bash -c 'echo hello-stdout; exit 7' ); rc=$?
echo "out=[$out] rc=$rc"
echo "-- S2 no shadow: bound still fires (sleep 10 under 1s)"
out=$( . "$lib"; s=$(date +%s); fm_run_timed 1 sleep 10; r=$?; echo "rc=$r elapsed=$(( $(date +%s)-s ))s timed_out=$(fm_timed_out $r && echo yes || echo no)" ); echo "$out"
echo "-- S3 shadowed: bound still fires"
out=$( timeout(){ echo shadowed; return 0; }; . "$lib"; s=$(date +%s); fm_run_timed 1 sleep 10; r=$?; echo "rc=$r elapsed=$(( $(date +%s)-s ))s" ); echo "$out"
echo "-- S4 fm_exec_timed with shadow function exported, stdout+status"
out=$( timeout(){ echo shadowed; return 0; }; export -f timeout; . "$lib"; ( FM_TIMEOUT_MECHANISM_OVERRIDE= ; fm_exec_timed 5 1 bash -c 'echo exec-out; exit 5' ) ); rc=$?; echo "out=[$out] rc=$rc"
echo "-- S5 fallback: PATH without timeout -> perl"
out=$( d=$(mktemp -d); for t in bash perl mktemp cat rm sleep kill date; do ln -s "$(type -P $t)" $d/$t; done; PATH=$d; timeout(){ echo shadowed; return 0; }; . "$lib"; echo "mechanism=$(fm_timeout_mechanism)"; fm_run_timed 5 bash -c 'echo fb-out; exit 3'; echo "rc=$?"; /usr/bin/rm -rf $d ); echo "$out"
echo "-- S6 override bash"
out=$( timeout(){ echo shadowed; return 0; }; . "$lib"; export FM_TIMEOUT_MECHANISM_OVERRIDE=bash; echo "mechanism=$(fm_timeout_mechanism)"; fm_run_timed 5 bash -c 'echo ov-out; exit 4'; echo "rc=$?" ); echo "$out"
