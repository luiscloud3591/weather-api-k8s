#!/bin/sh
# KAN-14: runs the load test and records the HPA every 15 seconds:
# about 4 minutes under load, then about 7 minutes after the load stops.
#
# Usage (from the repository root):
#   ./loadtest/run-and-record.sh [output-file]
# Default output file: hpa-timeline.txt

K="kubectl --context minikube -n weather-api"
MANIFEST="$(dirname "$0")/load-generator.yaml"
OUT="${1:-hpa-timeline.txt}"
: > "$OUT"

snap() {
  echo "$(date '+%H:%M:%S') | $1 | $($K get hpa weather-api --no-headers | awk '{print $3, $4, "replicas=" $7}') | pods_ready=$($K get pods -l app=weather-api --no-headers | grep -c ' 1/1 ')" >> "$OUT"
}

snap "baseline"
$K apply -f "$MANIFEST" >/dev/null
echo "$(date '+%H:%M:%S') | LOAD STARTED" >> "$OUT"
for i in $(seq 1 16); do sleep 15; snap "load"; done

$K top pods >> "$OUT" 2>&1
$K delete -f "$MANIFEST" >/dev/null
echo "$(date '+%H:%M:%S') | LOAD STOPPED" >> "$OUT"
for i in $(seq 1 28); do sleep 15; snap "cooldown"; done
echo "$(date '+%H:%M:%S') | END" >> "$OUT"
