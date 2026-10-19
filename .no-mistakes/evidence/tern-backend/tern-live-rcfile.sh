#!/usr/bin/env bash
# Live check of foreground classification with --rcfile on real tern.
# Touches only a session fm-test-rc-<pid> this run creates; guarded cleanup.
set -u
ROOT=$1; cd "$ROOT" || exit 1
SESSION_NAME="fm-test-rc-$$"; SID=""
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); bin/fm-lab-home.sh create "$LAB" >/dev/null || exit 1
export FM_HOME="$LAB" FM_TERN_SESSION="$SESSION_NAME" FM_BACKEND=tern
unset TMUX
. tests/tern-test-safety.sh; . bin/fm-backend.sh; fm_backend_source tern || exit 1
F=0; ok(){ echo "PASS: $*"; }; bad(){ echo "FAIL: $*"; F=$((F+1)); }
trap '[ -n "$SID" ] && tern_safe_kill_session "$SID" "$SESSION_NAME"; rm -rf "$LAB"' EXIT
SID=$(fm_backend_tern_container_ensure)
read -r TAB BLOCK <<<"$(fm_backend_tern_create_task fm-rc "$LAB")"; T="$SID:$BLOCK"; sleep 1.5
fg(){ tern process "$SID/$BLOCK" --json | jq -c '.foreground // . | {name, argv}' 2>/dev/null || tern process "$SID/$BLOCK" --json; }
echo "--- fresh shell foreground:"; fg
C=$(fm_backend_tern_foreground_class "$SID" "$BLOCK"); A=$(fm_backend_agent_state tern "$T"); echo "class=$C agent_state=$A"
[ "$C" = shell ] && [ "$A" = dead ] && ok "plain integration shell -> shell/dead" || bad "plain shell $C/$A"
fm_backend_tern_send_text_line "$T" "bash --init-file /dev/null" fm-rc; sleep 1.5
echo "--- nested bash --init-file X foreground:"; fg
C=$(fm_backend_tern_foreground_class "$SID" "$BLOCK"); A=$(fm_backend_agent_state tern "$T"); echo "class=$C agent_state=$A"
[ "$C" = shell ] && [ "$A" = dead ] && ok "--init-file value treated as option -> dead" || bad "init-file $C/$A"
fm_backend_tern_send_text_line "$T" "bash --rcfile /dev/null -c 'sleep 120; true'" fm-rc; sleep 1.5
echo "--- bash --rcfile X -c CMD foreground:"; fg
C=$(fm_backend_tern_foreground_class "$SID" "$BLOCK"); A=$(fm_backend_agent_state tern "$T"); echo "class=$C agent_state=$A"
[ "$C" = shell-command ] && [ "$A" != dead ] && ok "rcfile + -c command stays shell-command (not dead)" || bad "rcfile+cmd $C/$A"
echo FAILS=$F; exit $F
