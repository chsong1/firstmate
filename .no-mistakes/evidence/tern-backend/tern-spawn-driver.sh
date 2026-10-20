#!/usr/bin/env bash
# Real bin/fm-spawn.sh --backend tern against a PRIVATE tern daemon; fake treehouse/tmux
# from the suite fixtures, real tern. Then real fm-teardown against the same home.
set -u
ROOT=$1; LAB=$2
[ -n "${TERN_DAEMON_SOCKET:-}" ] || exit 2
cd "$ROOT/tests"; . ./lib.sh; . ./fixtures.sh
ID=ternlive-a1; D=$LAB/spawn
HOME_DIR=$D/home; PROJ=$D/project; WT=$D/wt
FAKEBIN=$D/fake/fakebin
cat > $FAKEBIN/codex <<'SH'
#!/bin/sh
echo "FAKE-HARNESS codex started in $(pwd) TERM_PROGRAM=${TERM_PROGRAM-unset}"; exec sleep 600
SH
chmod +x $FAKEBIN/codex
fm_test_spawn_home "$HOME_DIR" codex
fm_git_worktree "$PROJ" "$WT" wt-live
fm_test_spawn_brief "$HOME_DIR" "$ID"
export FM_TERN_SESSION=fm-test-spawnlive-$$ PATH="$FAKEBIN:$PATH"
echo "## spawn"
fm_test_run_spawn "$HOME_DIR" "$WT" "$FAKEBIN" "$ID" "$PROJ" --mode no-mistakes --yolo off --backend tern; echo "spawn rc=$?"
echo "## meta"; grep -E '^(backend|window|tern_|endpoint_task_id)' $HOME_DIR/state/$ID.meta
echo "## tern inventory"; tern ls --json | sed -E 's/("id"[[:space:]]*:[[:space:]]*)([0-9]+)/\1"\2"/g' | jq -c '.sessions[]|{id,name,tabs:[.tabs[]|{id,name,blocks:[.blocks[]|{id,keep_open,cwd}]}]}'
sleep 3
W=$(sed -n 's/^window=//p' $HOME_DIR/state/$ID.meta); S=${W%%:*}; B=${W##*:}
echo "## block capture"; tern capture "$S/$B" --scrollback --surfaces | grep -v '^\s*$' | tail -8
