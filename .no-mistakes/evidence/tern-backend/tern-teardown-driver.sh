#!/usr/bin/env bash
# Real bin/fm-teardown.sh on the task spawned by tern-spawn-driver.sh (private tern daemon).
set -u
ROOT=$1; LAB=$2; ID=ternlive-a1; D=$LAB/spawn; H=$D/home; FAKEBIN=$D/fake/fakebin
[ -n "${TERN_DAEMON_SOCKET:-}" ] || exit 2
td(){ env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_PROJECTS_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_GATE_REFUSE_BYPASS FM_HOME="$H" HOME="$H/user-home" CLAUDE_CONFIG_DIR= TMUX=fake,1,0 PATH="$FAKEBIN:$PATH" "$ROOT/bin/fm-teardown.sh" "$@" 2>&1; }
W=$(sed -n 's/^window=//p' $H/state/$ID.meta); S=${W%%:*}; B=${W##*:}
blk(){ tern ls --json | sed -E 's/("id"[[:space:]]*:[[:space:]]*)([0-9]+)/\1"\2"/g' | jq -c --arg b "$B" '[.sessions[].tabs[]|select(any(.blocks[];.id==$b))|{tab:.id,name}]'; }
echo "## A: captain renames the task tab, then teardown"
tern rename "$S/$B" "captain-scratch" >/dev/null; echo "tab now: $(blk)"
td $ID; echo "teardown rc=$?"
echo "block after: $(blk)"; ls $H/state/$ID.meta && echo "meta retained"
echo "## B: tab title restored, teardown again"
tern rename "$S/$B" "$(tern ls --json >/dev/null; echo fm-firstmate-59dff5a8-$ID)" >/dev/null; echo "tab now: $(blk)"
td $ID; echo "teardown rc=$?"
echo "block after: $(blk)"; ls $H/state/$ID.meta 2>&1
