#!/usr/bin/env bash
set -uo pipefail

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
review_log="/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log"
root="/fsx/analysis_results/ubuntu"
tmp="/tmp/hg003_hiomr_downsample_status_${stamp}.log"

mkdir -p "$(dirname "$review_log")"

{
  echo "===== ${stamp} heartbeat downsample status ====="
  echo "user=$(id -un) shell=$0 host=$(hostname)"
  echo "-- required commands --"
  for cmd in squeue tmux find awk sed grep tail ps df du; do
    command -v "$cmd" || { echo "MISSING:${cmd}"; exit 10; }
  done
  echo "-- fsx --"
  df -h /fsx
  echo "-- active workdirs --"
  find "$root" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort | grep -E 'hg003a_altair3_hiomr_ilmn(20x_ont5x|15x_ont10x|15x_ont7x|15x_ont5x|10x_ont10x|7x_ont7x|7x_ont5x|5x_ont5x)_1022' || true
  echo "-- squeue summary --"
  squeue -u ubuntu -h -o '%T' | awk '{n[$1]++} END {for (s in n) print s,n[s]; if (!NR) print "EMPTY 0"}'
  echo "-- squeue head --"
  squeue -u ubuntu | head -80
  echo "-- controllers --"
  ps -fu ubuntu | awk '/snakemake|dy-r|day_run/ && !/awk/ {print}'
  echo "-- tmux active sessions --"
  tmux ls | grep -E 'hg003a_altair3_hiomr_ilmn(20x_ont5x|15x_ont10x|15x_ont7x).*1022' || true

  check_run() {
    local id="$1"
    local wd="$2"
    local session="$3"
    local rc="$4"
    local daylog="$5"
    local repo="$root/$wd/daylily-omics-analysis"
    echo "-- ${id} ${wd} --"
    if [ ! -d "$root/$wd" ]; then
      echo "workdir_absent"
      return 0
    fi
    echo "workdir_present"
    echo "rc_file=${rc}"
    if [ -f "$rc" ]; then
      cat "$rc"
    else
      echo "rc_absent"
    fi
    for marker in "$root/$wd/daylily.successful_run" "$root/$wd/daylily.failed_run" "$repo/daylily.successful_run" "$repo/daylily.failed_run"; do
      if [ -e "$marker" ]; then
        stat -c 'marker %n %y %s' "$marker"
      fi
    done
    if tmux has-session -t "$session" 2>/dev/null; then
      local windows panes
      windows="$(tmux list-windows -t "$session" -F '#{window_index}' | wc -l | awk '{print $1}')"
      panes="$(tmux list-panes -a -F '#{session_name}' | awk -v s="$session" '$1 == s {n++} END {print n + 0}')"
      echo "tmux_session=${session} windows=${windows} panes=${panes}"
      tmux capture-pane -pt "$session" -S -20 | tail -20
    else
      echo "tmux_session_absent=${session}"
    fi
    if [ -d "$repo/.snakemake/log" ]; then
      local latest
      latest="$(find "$repo/.snakemake/log" -maxdepth 1 -type f -printf '%T@ %p\n' | sort -nr | awk 'NR==1 {print $2}')"
      echo "latest_snakemake_log=${latest:-none}"
      if [ -n "${latest:-}" ] && [ -f "$latest" ]; then
        grep -E '^[0-9]+ of [0-9]+ steps|steps \\([0-9]+%\\) done|Error in rule|MissingOutputException|MissingInputException|WorkflowError|Shutting down' "$latest" | tail -12 || true
      fi
    fi
    if [ -f "$repo/$daylog" ]; then
      echo "daylog_tail=$repo/$daylog"
      tail -20 "$repo/$daylog"
    fi
  }

  check_run "DS-003" "hg003a_altair3_hiomr_ilmn20x_ont5x_1022" "hg003a_altair3_hiomr_ilmn20x_ont5x_1022_run1024" "/tmp/hg003a_altair3_hiomr_ilmn20x_ont5x_1022.run1024.rc" "daylily_run_1024.log"
  check_run "DS-004" "hg003a_altair3_hiomr_ilmn15x_ont10x_1022" "hg003a_altair3_hiomr_ilmn15x_ont10x_1022_run1024_j190" "/tmp/hg003a_altair3_hiomr_ilmn15x_ont10x_1022.run1024_j190.rc" "daylily_run_1024_j190.log"
  check_run "DS-005" "hg003a_altair3_hiomr_ilmn15x_ont7x_1022" "hg003a_altair3_hiomr_ilmn15x_ont7x_1022_run1024_j190" "/tmp/hg003a_altair3_hiomr_ilmn15x_ont7x_1022.run1024_j190.rc" "daylily_run_1024_j190.log"
  echo "===== end ${stamp} heartbeat downsample status ====="
} | tee "$tmp"

cat "$tmp" >> "$review_log"
