#!/usr/bin/env bash
# Live A/B: real fm-home-summary-refresh.sh / fm-fleet-snapshot.sh on a disposable lab home.
set -u
WT=$1 EV=$2
BASE=$(mktemp -d /tmp/fm-base.XXXXXX)
git -C "$WT" archive 4869cf58 | tar -x -C "$BASE"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
TMUXD=$("$WT/bin/fm-lab-home.sh" tmux-dir "$LAB")
export TMUX_TMPDIR="$TMUXD"; unset TMUX
S=$LAB/state
printf '## In flight\n\n## Queued\n\n## Done\n' > "$LAB/data/backlog.md"
for id in sm1 sc2; do
  kind=secondmate; [ $id = sc2 ] && kind=scout
  mkdir -p "$LAB/projects/$id"
  printf 'window=firstmate:fm-%s\nworktree=%s\nproject=alpha\nharness=codex\nkind=%s\nmode=%s\nyolo=off\n' \
    $id "$LAB/projects/$id" $kind $kind > "$S/$id.meta"
  {
    printf 'working: starting\n'
    printf 'needs-decision [key=api-shape]: pick REST or RPC\n'
    printf 'blocked [key=quota]: provider quota exhausted\n'
    printf 'resolved [key=quota]: quota restored\n'
    for i in $(seq 1 1500); do printf 'working: filler line %04d of a long lived log\n' $i; done
  } > "$S/$id.status"
done
echo "== seed drain cursors (writing-mode fold, the bin/fm-wake-drain.sh path)"
for id in sm1 sc2; do
  k=secondmate; [ $id = sc2 ] && k=scout
  ( time bash -c '. "$1/bin/fm-classify-lib.sh"; status_open_decisions_incremental "$2" "" "" "$3" >/dev/null' _ "$WT" "$S/$id.status" $k ) 2>&1 | grep real
done
printf 'needs-decision [key=fresh-ask]: appended after the drain\nworking: tail\n' >> "$S/sm1.status"
printf 'resolved [key=api-shape]: answered\n' >> "$S/sc2.status"
wc -c "$S"/*.status
before=$(cksum "$S"/.*.open-decisions-cursor)
ls -la "$S" > "$EV/lab-state-before.txt"
run() { # label root
  local t0 t1
  t0=$(date +%s.%N)
  FM_HOME="$LAB" FM_HOME_SUMMARY_TIMEOUT=120 "$2/bin/fm-home-summary-refresh.sh"; rc=$?
  t1=$(date +%s.%N)
  printf '%s: refresh rc=%s elapsed=%.2fs\n' "$1" $rc "$(echo "$t1 - $t0" | bc)"
  jq -c '[.decisions_open[] | {task: (.task // .id // .task_id), key, verb}] ' "$S/home-summary.json" > "$EV/decisions-$1.json"
  cat "$EV/decisions-$1.json"
  FM_HOME="$LAB" "$2/bin/fm-fleet-snapshot.sh" --json | jq -c '[.tasks[] | {id, open: [.hints.open_decisions[] | .key]}]'
}
echo "== base (4869cf58, whole-file fold)"; run base "$BASE"
echo "== target (ed0450bc, read-only incremental fold)"; run target "$WT"
after=$(cksum "$S"/.*.open-decisions-cursor)
[ "$before" = "$after" ] && echo "drain cursors byte-identical after target runs: YES" || echo "drain cursors CHANGED"
ls "$S" | grep -E 'open-decisions|\.read\.' ; echo "-- no stray span chunks beside status: $(ls -a "$S" | grep -c '\.read\.')"
cmp -s "$EV/decisions-base.json" "$EV/decisions-target.json" && echo "published decisions_open identical base vs target: YES" || echo "DIFFER"
echo "== adversarial: corrupt sm1 cursor, target run must fall back to whole fold and leave cursor alone"
printf 'garbage\n' > "$S/.sm1.open-decisions-cursor"; c1=$(cksum "$S/.sm1.open-decisions-cursor")
FM_HOME="$LAB" "$WT/bin/fm-fleet-snapshot.sh" --json | jq -c '[.tasks[] | {id, open: [.hints.open_decisions[] | .key]}]'
[ "$c1" = "$(cksum "$S/.sm1.open-decisions-cursor")" ] && echo "corrupt cursor untouched: YES"
echo "== adversarial: delete cursors, target run writes none"
rm -f "$S"/.*.open-decisions-cursor
FM_HOME="$LAB" "$WT/bin/fm-fleet-snapshot.sh" --json | jq -c '[.tasks[] | {id, open: [.hints.open_decisions[] | .key]}]'
echo "cursors after run: $(ls -a "$S" | grep -c open-decisions-cursor)"
"$WT/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1
rm -rf "$LAB" "$BASE"
