#!/usr/bin/env bash
set -u
W=/home/user/.no-mistakes/worktrees/2573d6130b22/01M6PQ0JF8AWZE27ZHYNZ8P2G9
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
BASE=$(mktemp -d "${TMPDIR:-/tmp}/fm-base.XXXXXX")
trap 'TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server 2>/dev/null; rm -rf "$LAB" "$BASE"' EXIT
"$W/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux" "$LAB/projects/t1"
(cd "$W" && git archive b77b66cb bin) | tar -x -C "$BASE"
export TMUX_TMPDIR="$LAB/tmux"
tmux -L fm-lab new-session -d -s firstmate -n fm-t1 'sleep 600'
printf '## In flight\n\n## Queued\n\n## Done\n' > "$LAB/data/backlog.md"
cat > "$LAB/state/t1.meta" <<M
window=firstmate:fm-t1
worktree=$LAB/projects/t1
project=alpha
harness=codex
kind=secondmate
mode=secondmate
yolo=off
M
S="$LAB/state/t1.status"
{
printf 'needs-decision [key=api-shape]: pick REST or RPC\n'
printf 'blocked [key=quota]: provider quota exhausted\n'
printf 'resolved [key=quota]: quota restored\n'
for i in $(seq 1 6000); do printf 'working: long-lived filler %05d\n' "$i"; done
} > "$S"
echo "== status log: $(wc -l < "$S") lines, $(wc -c < "$S") bytes"
# warm the drain cursor via the library's writing path (what fm-watch.sh does)
C="$LAB/state/.t1.open-decisions-cursor"
echo "== running real bin/fm-wake-drain.sh in the lab to warm the drain cursor"
env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS FM_HOME="$LAB" "$W/bin/fm-wake-drain.sh" > "$LAB/drain.out" 2>&1; echo "drain exit=$?"
grep -A3 "OPEN DECISIONS" "$LAB/drain.out" | head -5
[ -f "$C" ] && echo "drain wrote cursor: $(head -2 "$C" | tr '\n' ' ')" || { echo "drain wrote no cursor; output:"; tail -5 "$LAB/drain.out"; }
printf 'needs-decision [key=fresh]: appended after the drain cursor\n' >> "$S"
before=$(cksum < "$C"); ls -A "$LAB/state" > "$LAB/ls.before"
echo "== whole-file oracle (status_open_decisions):"
bash -c '. "$1"; status_open_decisions "$2" secondmate' _ "$W/bin/fm-classify-lib.sh" "$S" | cut -f1,2
echo "== target snapshot hints.open_decisions:"
t0=$(date +%s.%N)
FM_OPEN_DECISIONS_READ_PROBE="$LAB/probe.tsv" FM_HOME="$LAB" "$W/bin/fm-fleet-snapshot.sh" --json | jq -c '.tasks[]|select(.id=="t1")|{pending:.hints.pending_decision,blocked:.hints.blocked_event,open:[.hints.open_decisions[]|{key,verb}]}'
t1=$(date +%s.%N)
echo "== read probe (bytes the target fold read): $(cut -f2 "$LAB/probe.tsv" | paste -sd,)  appended after drain cursor: $(( $(wc -c < "$S") - 198132 ))"
echo "== base snapshot hints.open_decisions:"
FM_HOME="$LAB" "$BASE/bin/fm-fleet-snapshot.sh" --json | jq -c '.tasks[]|select(.id=="t1")|{pending:.hints.pending_decision,blocked:.hints.blocked_event,open:[.hints.open_decisions[]|{key,verb}]}'
t2=$(date +%s.%N)
printf '== wall time: target %.2fs  base %.2fs\n' "$(echo "$t1-$t0"|bc)" "$(echo "$t2-$t1"|bc)"
after=$(cksum < "$C"); ls -A "$LAB/state" > "$LAB/ls.after"
[ "$before" = "$after" ] && echo "== drain cursor unchanged by snapshot: yes" || echo "== drain cursor CHANGED"
diff "$LAB/ls.before" "$LAB/ls.after" >/dev/null && echo "== state/ file set unchanged: yes" || { echo "== state/ changed:"; diff "$LAB/ls.before" "$LAB/ls.after"; }
echo "== home summary producer (target):"
FM_HOME="$LAB" FM_HOME_SUMMARY_TIMEOUT=120 "$W/bin/fm-home-summary-refresh.sh"; echo "exit=$?"
jq -c '[.decisions_open[]|{key,verb}]' "$LAB/state/home-summary.json"
echo "== adversarial: resolve 'fresh' after cursor, truncate-and-replace log"
printf 'resolved [key=fresh]: captain answered\n' >> "$S"
FM_HOME="$LAB" "$W/bin/fm-fleet-snapshot.sh" --json | jq -c '[.tasks[]|select(.id=="t1")|.hints.open_decisions[]|.key]'
printf 'needs-decision [key=newgen]: replaced log\n' > "$S.new"; mv "$S.new" "$S"
FM_HOME="$LAB" "$W/bin/fm-fleet-snapshot.sh" --json | jq -c '[.tasks[]|select(.id=="t1")|.hints.open_decisions[]|.key]'
bash -c '. "$1"; status_open_decisions "$2" secondmate' _ "$W/bin/fm-classify-lib.sh" "$S" | cut -f1 | paste -sd, | sed 's/^/oracle: /'
[ "$before" = "$(cksum < "$C")" ] && echo "== drain cursor still unchanged: yes" || echo "== drain cursor CHANGED"
