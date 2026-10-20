#!/usr/bin/env bash
# Drives bin/backends/tern.sh via bin/fm-backend.sh against a PRIVATE tern
# daemon (TERN_DAEMON_SOCKET), never the operator's live window daemon.
set -u
ROOT=$1
[ -n "${TERN_DAEMON_SOCKET:-}" ] || { echo "refuse: no private TERN_DAEMON_SOCKET"; exit 2; }
. "$ROOT/bin/fm-backend.sh"
fm_backend_source tern || exit 2
export FM_TERN_SESSION=fm-test-lab-$$
ok(){ printf 'PASS - %s\n' "$1"; }; bad(){ printf 'FAIL - %s\n' "$1"; FAILS=$((FAILS+1)); }; FAILS=0
ls_ids(){ tern ls --json | sed -E 's/("id"[[:space:]]*:[[:space:]]*)([0-9]+)/\1"\2"/g'; }

echo "## S1 container + task creation"
SID=$(fm_backend_tern_container_ensure) && ok "container_ensure -> session id $SID" || bad "container_ensure"
read -r TAB BID <<<"$(fm_backend_tern_create_task fm-alpha /tmp)" || bad create
[ -n "$BID" ] || { echo "FATAL no block id"; exit 9; }; T="$SID:$BID"; echo "target=$T tab=$TAB"
ls_ids | jq -c --arg s "$SID" '.sessions[]|select(.id==$s)|{name,tabs:[.tabs[]|{id,name,blocks:[.blocks[]|{id,keep_open}]}]}'
fm_backend_target_exists tern "$T" fm-alpha && ok "target_exists with label fm-alpha" || bad "target_exists"
fm_backend_target_exists tern "$T" fm-other 2>/dev/null && bad "target_exists accepted wrong label" || ok "target_exists refuses wrong label fm-other"
fm_backend_tern_create_task fm-alpha /tmp >/dev/null 2>$TMPDIR/dup.err && bad "duplicate title accepted" || ok "duplicate create of fm-alpha refused: $(cat $TMPDIR/dup.err)"

echo "## S2 send + capture"
sleep 1
fm_backend_tern_send_text_line "$T" 'echo hello-from-firstmate-tern' fm-alpha || bad send_text_line
sleep 0.8
out=$(fm_backend_capture tern "$T" 20 fm-alpha); printf '%s\n' "$out" | tail -5
case "$out" in *hello-from-firstmate-tern*) ok "capture shows sent line";; *) bad "capture missing line";; esac
fm_backend_send_key tern "$T" Escape fm-alpha && fm_backend_send_key tern "$T" C-c fm-alpha && ok "send_key Escape/C-c accepted" || bad send_key
p=$(fm_backend_tern_current_path "$T" fm-alpha); [ "$p" = /tmp ] && ok "current_path=$p" || bad "current_path=$p"

echo "## S3 native state degrades without a window ctl endpoint"
ns=$(fm_backend_tern_native_state "$T" fm-alpha); bs=$(fm_backend_busy_state tern "$T"); as=$(fm_backend_agent_state tern "$T")
echo "native=$ns busy=$bs agent=$as"
[ "$ns" = unknown ] && [ "$bs" != busy ] && ok "native_state=unknown, busy_state=$bs (no hard error)" || bad "native/busy"

echo "## S4 kill refuses a renamed task tab (user decision review-1)"
tern rename "$SID/$BID" "captain-renamed-this" >/dev/null 2>&1 || tern rename --help 2>&1 | head -5
ls_ids | jq -c --arg s "$SID" --arg t "$TAB" '.sessions[]|select(.id==$s)|.tabs[]|select(.id==$t)|{id,name}'
fm_backend_kill tern "$T" "" fm-alpha 2>$TMPDIR/kill.err; rc=$?
echo "kill rc=$rc stderr: $(cat $TMPDIR/kill.err)"
still=$(ls_ids | jq -r --arg s "$SID" --arg b "$BID" '.sessions[]|select(.id==$s)|.tabs[].blocks[]|select(.id==$b)|.id')
[ $rc -ne 0 ] && [ "$still" = "$BID" ] && ok "renamed tab: kill rc=$rc, block $BID still open" || bad "renamed kill rc=$rc still=$still"

echo "## S5 kill refuses a block from another session / malformed target"
SID_OTHER=$(tern new session --json fm-test-lab-other-$$ 2>/dev/null | sed -E 's/("id"[[:space:]]*:[[:space:]]*)([0-9]+)/\1"\2"/g' | jq -r '.session // .id // empty')
echo "other session id=${SID_OTHER:-?}"
if [ -n "$SID_OTHER" ]; then
  fm_backend_kill tern "$SID_OTHER:$BID" "" fm-alpha 2>$TMPDIR/k2.err; rc=$?
  echo "kill rc=$rc stderr: $(cat $TMPDIR/k2.err)"
  [ $rc -ne 0 ] && ok "cross-session target refused" || bad "cross-session target accepted"
fi
fm_backend_kill tern "abc:1;rm" "" fm-alpha 2>$TMPDIR/k3.err; rc=$?; echo "malformed rc=$rc $(cat $TMPDIR/k3.err)"
[ $rc -ne 0 ] && ok "malformed target refused" || bad "malformed accepted"

echo "## S6 kill happy path + idempotent absent"
tern rename "$SID/$BID" "fm-$(fm_backend_tern_home_label)-alpha" >/dev/null 2>&1
read -r TAB2 BID2 <<<"$(fm_backend_tern_create_task fm-beta /tmp)"
live=$(fm_backend_tern_list_live); echo "list_live:"; printf '%s\n' "$live"
case "$live" in *"$SID:$BID2"*fm-beta*) ok "list_live finds fm-beta";; *) bad "list_live";; esac
fm_backend_kill tern "$SID:$BID2" "" fm-beta; rc=$?
still=$(ls_ids | jq -r --arg b "$BID2" '.sessions[].tabs[].blocks[]|select(.id==$b)|.id')
[ $rc -eq 0 ] && [ -z "$still" ] && ok "kill closed fm-beta block $BID2" || bad "kill happy rc=$rc"
fm_backend_kill tern "$SID:$BID2" "" fm-beta && ok "repeat kill of absent block returns 0" || bad "repeat kill"
[ "$(fm_backend_agent_state tern "$SID:$BID2")" = missing ] && ok "agent_state=missing after kill" || bad "agent_state after kill"
echo "## final inventory"; ls_ids | jq -c '.sessions[]|{id,name,tabs:[.tabs[]|{name,blocks:[.blocks[].id]}]}'
echo "FAILS=$FAILS"; exit $FAILS
