#!/bin/zsh
# Checks sirat4mac's prayer times against Sirat's own yearly calendar
# (prayer_times_<year>.json), day by day, including summer/winter time changes.
set -euo pipefail
cd "$(dirname "$0")/.."

DATA="/Applications/Sirat.app/Wrapper/Runner.app/Frameworks/App.framework/flutter_assets/assets/data"
REF=$(ls "$DATA"/prayer_times_*.json 2>/dev/null | tail -1 || true)
if [[ -z "$REF" ]]; then
  echo "Sirat's yearly calendar was not found in $DATA" >&2
  exit 1
fi
YEAR=$(basename "$REF" | grep -oE '[0-9]{4}')

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The app's code without its startup block, plus a small harness that prints a year of times.
sed '/^MainActor.assumeIsolated {/,$d' Sources/main.swift > "$WORK/main.swift"
cat >> "$WORK/main.swift" <<'EOF'
let year = Int(CommandLine.arguments[1])!
let t = Takvim(def: profileDefs[0])!
let hm = DateFormatter(); hm.timeZone = t.timeZone; hm.dateFormat = "H:mm"
let ymd = DateFormatter(); ymd.timeZone = t.timeZone; ymd.dateFormat = "yyyy-MM-dd"
var day = t.calendar.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12))!
while t.calendar.component(.year, from: day) == year {
    let times = t.times(for: day, shiftMinutes: 0)
    print(ymd.string(from: day) + " " + times.map { "\($0.0.key)=\(hm.string(from: $0.1))" }.joined(separator: " "))
    day = t.calendar.date(byAdding: .day, value: 1, to: day)!
}
EOF

swiftc -swift-version 5 -framework Cocoa -framework ServiceManagement "$WORK/main.swift" -o "$WORK/harness"
"$WORK/harness" "$YEAR" > "$WORK/out.txt"

python3 -I - "$REF" "$WORK/out.txt" <<'EOF'
import json, sys
ref = {r["date"]: r for r in json.load(open(sys.argv[1]))["rows"]}
days = bad = 0
for line in open(sys.argv[2]):
    date, *pairs = line.split()
    if date not in ref:
        continue
    days += 1
    for key, ours in (p.split("=") for p in pairs):
        if ref[date][key] != ours:
            bad += 1
            print(f"MISMATCH {date} {key}: sirat4mac {ours}, Sirat {ref[date][key]}")
print(f"Checked {days} days: {bad} mismatches")
sys.exit(1 if bad or not days else 0)
EOF
