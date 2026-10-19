#!/usr/bin/env bash
# Waybar date+time widget: time as text, scripted calendar tooltip.
# The tooltip shows three months side by side: previous, current, next
# (waybar's built-in {calendar} cannot do multi-month windows).
set -euo pipefail

time_text="$(date +'%a %d %b  %H:%M')"

if command -v cal >/dev/null 2>&1; then
    cal="$(cal -3)"
else
    # no cal(1) from bsdmainutils: build the 3-month calendar with python
    cal="$(python3 - <<'PY'
import calendar, datetime
today = datetime.date.today()
months = []
for m in (today.month - 1, today.month, today.month + 1):
    y = today.year + (m - 1) // 12
    months.append(calendar.TextCalendar(6).formatmonth(y, (m - 1) % 12 + 1))
blocks = [b.splitlines() for b in months]
width = max(len(l) for b in blocks for l in b) + 3
lines = max(len(b) for b in blocks)
for row in range(lines):
    print("".join(b[row].ljust(width) if row < len(b) else " " * width
                  for b in blocks).rstrip())
PY
)"
fi

# the grid's width in monospace columns; pad the header to center it
width="$(awk 'BEGIN {m=0} {if (length($0)>m) m=length($0)} END {print m}' <<<"${cal}")"
header="$(date +'%A, %d %B')"
pad=$(( (width - ${#header}) / 2 ))
(( pad < 1 )) && pad=1
hdr_line="$(printf "%${pad}s" "")${header}"

jq -cn --arg text "${time_text}" \
       --arg hdr "${hdr_line}" \
       --arg cal "${cal}" \
       '{text: $text, class: "",
         tooltip: ("<tt><small><b>" + $hdr + "</b>\n\n" + $cal + "</small></tt>")}'