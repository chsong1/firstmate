#!/usr/bin/env bash
# Live perf A/B: a decision-heavy 1,500-line log, drain cursor current, 3 lines appended.
set -u
WT=$1
BASE=$(mktemp -d /tmp/fm-base.XXXXXX); git -C "$WT" archive 4869cf58 | tar -x -C "$BASE"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); "$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
export TMUX_TMPDIR=$("$WT/bin/fm-lab-home.sh" tmux-dir "$LAB"); unset TMUX
S=$LAB/state; printf '## In flight\n\n## Queued\n\n## Done\n' > "$LAB/data/backlog.md"
mkdir -p "$LAB/projects/sm1"
printf 'window=firstmate:fm-sm1\nworktree=%s\nproject=alpha\nharness=codex\nkind=secondmate\nmode=secondmate\nyolo=off\n' "$LAB/projects/sm1" > "$S/sm1.meta"
{ for i in $(seq 1 750); do
    printf 'needs-decision [key=q%04d]: question %d for the captain\n' $i $i
    printf 'resolved [key=q%04d]: answered\n' $i
  done; printf 'needs-decision [key=still-open]: long-standing ask\n'; } > "$S/sm1.status"
echo "status lines: $(wc -l < "$S/sm1.status")"
echo "drain-path cursor seed:"; ( time bash -c '. "$1/bin/fm-classify-lib.sh"; status_open_decisions_incremental "$2" "" "" secondmate >/dev/null' _ "$WT" "$S/sm1.status" ) 2>&1 | grep real
printf 'needs-decision [key=fresh-ask]: appended\nworking: tail\nresolved [key=still-open]: answered at last\n' >> "$S/sm1.status"
for pair in "base:$BASE" "target:$WT"; do
  l=${pair%%:*} r=${pair#*:}
  t0=$(date +%s.%N); FM_HOME="$LAB" FM_HOME_SUMMARY_TIMEOUT=120 "$r/bin/fm-home-summary-refresh.sh"; rc=$?; t1=$(date +%s.%N)
  printf '%s: fm-home-summary-refresh rc=%s elapsed=%.2fs decisions_open=%s\n' $l $rc "$(echo "$t1-$t0"|bc)" "$(jq -c '[.decisions_open[]|.key]' "$S/home-summary.json")"
done
"$WT/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1; rm -rf "$LAB" "$BASE"
