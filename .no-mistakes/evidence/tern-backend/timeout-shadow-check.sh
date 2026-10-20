# A shell function named `timeout` (stand-in for omp's builtin) must not be what fm_run_timed runs.
ROOT=$1; REV=$2
. <(git -C "$ROOT" show "$REV:bin/fm-timeout-lib.sh")
timeout() { echo "SHADOW timeout called: $*" >&2; "$@"; }   # runs unbounded, like a non-bounding builtin
echo "[$REV] mechanism=$(fm_timeout_mechanism)"
s=$(date +%s.%N); fm_run_timed 1 sleep 5; rc=$?; e=$(date +%s.%N)
printf '[%s] fm_run_timed 1 sleep 5 -> rc=%s elapsed=%.1fs\n' "$REV" "$rc" "$(echo "$e - $s" | bc)"
