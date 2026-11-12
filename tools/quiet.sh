#!/usr/bin/env bash
# quiet.sh -- VM quiet protocol for measurement/recording windows (sanoba-audio line).
#
# PURPOSE: pause managed background jobs that can spawn heavy work, so audio/video
# captures run on an effectively exclusive VM; restore them afterwards, verifiably.
#
# AUDITED PAUSE SET (user-managed crons, from cron.list 2026-11-13):
#   vn-arcade-dev-loop        interval 1h  (autonomous dev loop -- heavy)
#   bluesky-continuous-posting interval 3h (agent + posting work)
#   agentic-feature-tour      daily 09:37  (agent run)
# EXCLUDED (documented): heartbeat (30m, light), epic-knightica-claim (runonce,
# time-sensitive), fish-voice-resume (runonce, far future), all is_system jobs
# (feed-pulse x24, deterministic-doctor, profile-image -- runtime-managed, the
# cron tool cannot disable them). Hooks: none exist (hooks.list empty).
#
# MECHANICS: cron state can only be flipped with the cron tool (no CLI exists),
# so this script manages the STATE FILE + watchdog + monitoring, and prints the
# exact job list for the operator agent to flip (and to verify afterwards with
# cron.list). A crashed session cannot leave jobs paused forever: the watchdog
# writes RESTORE_DUE at the deadline (default 6h) and the state file persists
# until `stop` clears it; any later session can run `stop` to restore.
set -u
SA=$HOME/workspace/sanoba-audio
ST=$SA/quiet.state; WDPIDF=$SA/quiet.watchdog.pid; MAXH=${QUIET_MAX_HOURS:-6}
JOBS="vn-arcade-dev-loop bluesky-continuous-posting agentic-feature-tour"
case "${1:-}" in
  start)
    [ -f "$ST" ] && { echo "quiet already active:"; cat "$ST"; exit 1; }
    NOW=$(date +%s); DUE=$((NOW + MAXH*3600))
    { echo "started_epoch=$NOW"; echo "restore_due_epoch=$DUE"; echo "jobs=$JOBS"; } > "$ST"
    ( sleep $((MAXH*3600)); echo "RESTORE_DUE $(date '+%F %T')" >> "$ST.due" ) &
    echo $! > "$WDPIDF"; disown 2>/dev/null || true
    echo "quiet state written. OPERATOR: disable these jobs via cron.update enabled=false, then verify with cron.list:"
    for j in $JOBS; do echo "  PAUSE $j"; done
    echo "auto-restore deadline: $(date -d @$DUE '+%F %T') (watchdog writes quiet.state.due)" ;;
  stop)
    [ -f "$ST" ] || { echo "quiet not active (nothing to restore)"; exit 0; }
    echo "OPERATOR: re-enable these jobs via cron.update enabled=true, then verify with cron.list:"
    grep '^jobs=' "$ST" | cut -d= -f2 | tr ' ' '\n' | sed 's/^/  RESTORE /'
    [ -f "$WDPIDF" ] && kill $(cat "$WDPIDF") 2>/dev/null
    rm -f "$ST" "$WDPIDF" "$ST.due"; echo "quiet state cleared" ;;
  status)
    if [ -f "$ST" ]; then echo "ACTIVE"; cat "$ST"; [ -f "$ST.due" ] && echo "*** RESTORE OVERDUE ***"; else echo "inactive"; fi
    uptime; echo "-- top CPU --"; ps aux --sort=-%cpu | head -6 | awk '{printf "%s %s%% %s\n",$2,$3,$11}' ;;
  monitor) # monitor <logfile> <secs> : log unexpected heavy processes during a window
    LF=$2; END=$(( $(date +%s) + ${3:-300} ))
    while [ $(date +%s) -lt $END ]; do
      ps aux --sort=-%cpu | awk 'NR>1 && $3>25 {printf "%s %s%% %s %s\n", $2,$3,$11,$12}' | grep -vE "qemu-i386|pulseaudio|parec|ffmpeg|matrix|runbench|quiet" >> "$LF.unexpected" 2>/dev/null
      sleep 20; done ;;
  *) echo "usage: quiet.sh start|stop|status|monitor <logfile> <secs>"; exit 2 ;;
esac
