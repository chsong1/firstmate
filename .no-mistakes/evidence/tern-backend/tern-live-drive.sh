#!/usr/bin/env bash
# Live drive of the tern backend against the REAL tern 0.9.4 daemon on this host.
# Touches ONLY a session named fm-test-live-<pid> that this run creates, and
# cleans it up through tests/tern-test-safety.sh's guarded kill.
# Usage: tern-live-drive.sh <worktree-root>
set -u
ROOT=$1
cd "$ROOT" || exit 1
SESSION_NAME="fm-test-live-$$"
SID=""
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
bin/fm-lab-home.sh create "$LAB" >/dev/null || { echo "lab create failed"; exit 1; }
export FM_HOME="$LAB" FM_TERN_SESSION="$SESSION_NAME" FM_BACKEND=tern
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE TMUX
. tests/tern-test-safety.sh
. bin/fm-backend.sh
fm_backend_source tern || exit 1

FAILS=0
step() { printf '\n=== %s\n' "$*"; }
ok() { printf 'PASS: %s\n' "$*"; }
bad() { printf 'FAIL: %s\n' "$*"; FAILS=$((FAILS + 1)); }
ls_block() {  # <block> -> "<session-id> <tab-name>" or empty
  tern_test_ls_json | jq -r --arg b "$1" '.sessions[] as $s | $s.tabs[] as $t | $t.blocks[] | select(.id == $b) | "\($s.id) \($t.name // "null")"'
}
cleanup() {
  local id=$SID
  [ -n "$id" ] || id=$(tern_test_ls_json | jq -r --arg n "$SESSION_NAME" '.sessions[] | select(.name == $n) | .id' | head -1)
  [ -n "$id" ] && tern_safe_kill_session "$id" "$SESSION_NAME"
  rm -rf "$LAB"
}
trap cleanup EXIT

step "container_ensure creates session $SESSION_NAME (lab FM_HOME=$LAB)"
SID=$(fm_backend_tern_container_ensure) && ok "session id $SID" || bad "container_ensure"
tern_test_ls_json | jq -c --arg n "$SESSION_NAME" '.sessions[] | select(.name == $n) | {id, name, tabs: [.tabs[] | {id, name}]}'

step "create_task fm-livetask (keep-open tab renamed to scoped title, read back)"
TITLE=$(fm_backend_tern_scoped_title fm-livetask); echo "scoped title: $TITLE"
read -r TAB BLOCK <<<"$(fm_backend_tern_create_task fm-livetask "$LAB")" || bad "create_task"
T="$SID:$BLOCK"; echo "target=$T tab=$TAB"
echo "listed: $(ls_block "$BLOCK")"
[ "$(ls_block "$BLOCK")" = "$SID $TITLE" ] && ok "tab title pinned to $TITLE after rename" || bad "title not pinned"
fm_backend_target_exists tern "$T" fm-livetask && ok "target_exists with label" || bad "target_exists"
fm_backend_target_exists tern "$T" fm-other 2>/dev/null && bad "target_exists accepted wrong label" || ok "target_exists refuses wrong label"

step "duplicate create_task for the same label refuses"
fm_backend_tern_create_task fm-livetask "$LAB" && bad "duplicate created" || ok "duplicate refused"

step "send_literal + send_key Enter, send_text_line, capture/visible_capture"
sleep 1
fm_backend_tern_send_literal "$T" 'echo literal-then-key-tern' fm-livetask; sleep 0.3
fm_backend_tern_send_key "$T" Enter fm-livetask; sleep 0.8
fm_backend_tern_send_text_line "$T" 'echo composed-line-tern' fm-livetask; sleep 0.8
CAP=$(fm_backend_tern_capture "$T" 20 fm-livetask); printf '%s\n' "$CAP" | tail -6
case "$CAP" in *literal-then-key-tern*composed-line-tern*) ok "capture shows both sent lines' output" ;; *) bad "capture missing output" ;; esac
VIS=$(fm_backend_tern_visible_capture "$T" fm-livetask)
case "$VIS" in *composed-line-tern*) ok "visible_capture shows latest line" ;; *) bad "visible_capture" ;; esac
for k in Escape C-c C-u Enter; do fm_backend_tern_send_key "$T" "$k" fm-livetask && ok "key $k accepted by real tern" || bad "key $k rejected"; done

step "current_path, agent_state, busy_state, native_state (no ctl window on this host)"
fm_backend_tern_send_text_line "$T" "cd /tmp" fm-livetask; sleep 0.6
echo "current_path=$(fm_backend_tern_current_path "$T" fm-livetask)"
AS=$(fm_backend_agent_state tern "$T"); BS=$(fm_backend_busy_state tern "$T"); NS=$(fm_backend_tern_native_state "$T" fm-livetask)
echo "agent_state=$AS busy_state=$BS native_state=$NS"
[ "$AS" = dead ] && ok "shell-only block reads dead" || bad "agent_state $AS"
[ "$BS" = unknown ] && [ "$NS" = unknown ] && ok "ctl failure degrades to unknown, not an error" || bad "native degrade"

step "list_live discovers the task by title"
fm_backend_tern_list_live

step "ADVERSARIAL: rename the task tab out from under firstmate, then kill"
tern rename "$SID/$BLOCK" "hand-renamed-by-user" >/dev/null; sleep 0.3
echo "listed after rename: $(ls_block "$BLOCK")"
fm_backend_send_text_submit tern "$T" 'echo should-not-land' 1 0.2 0.2 fm-livetask 2>&1 | sed 's/^/send> /'
fm_backend_kill tern "$T" "" fm-livetask; RC=$?
echo "fm_backend_kill rc=$RC"
[ "$RC" -ne 0 ] && ok "kill refused (nonzero) for renamed tab" || bad "kill returned 0 on renamed tab"
[ -n "$(ls_block "$BLOCK")" ] && ok "renamed block still open (nothing closed)" || bad "renamed block was closed"
fm_backend_list_live tern 2>/dev/null | grep -q "$BLOCK" && bad "list_live still claims renamed tab" || ok "list_live no longer claims the renamed tab"

step "Real fm-teardown.sh on a lab task record whose tab was renamed"
mkdir -p "$LAB/state" "$LAB/data/livetask"; echo "# live report" > "$LAB/data/livetask/report.md"
cat > "$LAB/state/livetask.meta" <<EOF
window=$T
endpoint_task_id=livetask
backend=tern
tern_session_id=$SID
tern_tab_id=$TAB
tern_block_id=$BLOCK
kind=scout
worktree=$LAB/gone-worktree
project=$LAB/gone-project
EOF
bin/fm-captain-hold.sh complete livetask --none; echo "captain-hold complete rc=$?"
bin/fm-teardown.sh livetask; RC=$?
echo "fm-teardown rc=$RC"; ls "$LAB/state"
[ "$RC" -ne 0 ] && [ -f "$LAB/state/livetask.meta" ] && ok "teardown refused and kept livetask.meta" || bad "teardown dropped records for renamed tab"
[ -n "$(ls_block "$BLOCK")" ] && ok "block survives refused teardown" || bad "block closed by teardown"

step "Restore scoped title; teardown now closes the block and removes the record"
tern rename "$SID/$BLOCK" "$TITLE" >/dev/null; sleep 0.3
echo "listed: $(ls_block "$BLOCK")"
bin/fm-teardown.sh livetask; RC=$?
echo "fm-teardown rc=$RC"; ls "$LAB/state"
sleep 0.5
[ -z "$(ls_block "$BLOCK")" ] && ok "block closed by teardown" || bad "block still open"
[ ! -f "$LAB/state/livetask.meta" ] && ok "meta removed after verified close" || bad "meta kept after close (rc=$RC)"
fm_backend_kill tern "$T" "" fm-livetask && ok "repeat kill of gone block returns 0" || bad "repeat kill"

step "ADVERSARIAL: kill with a target whose block lives in a different (second fm-test) session refuses"
SESSION2="fm-test-live2-$$"
SID2=$(FM_TERN_SESSION=$SESSION2 fm_backend_tern_container_ensure)
read -r _T2 B2 <<<"$(FM_TERN_SESSION=$SESSION2 fm_backend_tern_create_task fm-other "$LAB")"
fm_backend_kill tern "$SID:$B2" "" fm-other; RC=$?
echo "rc=$RC; block $B2 still listed: $(ls_block "$B2")"
[ "$RC" -ne 0 ] && [ -n "$(ls_block "$B2")" ] && ok "moved block refused, untouched" || bad "moved block"
tern_safe_kill_session "$SID2" "$SESSION2" && ok "second session cleaned via guard" || bad "second cleanup"
fm_backend_kill tern "1/2" 2>&1; [ $? -ne 0 ] && ok "malformed target refused" || bad "malformed target"

printf '\nFAILS=%s\n' "$FAILS"
exit "$FAILS"
