#!/usr/bin/env bash
# Check the image answers for exactly the areas README.md claims to cover.
#
# The coverage table is the interesting part of this repository -- the gaps are
# not visible from the dataset titles, and a query outside coverage returns
# null rather than an error. This keeps the table honest.
#
#   usage: verify-coverage.sh [image]

set -euo pipefail

IMAGE="${1:-outdoorsafetylab/moidemd}"

# Elevations outside this band mean the georeferencing is wrong rather than the
# coverage: Taiwan's highest point is 3952 m and its lowest land sits a little
# below sea level. A bare "not null" check would pass a grossly offset raster.
MIN_M=-50
MAX_M=4100

# Reduces a response to one token: a number, "null", or why it was rejected.
# Without this an HTML error body would count as an elevation.
read -r -d '' PARSE <<'PY' || true
import json, math, sys
raw = sys.stdin.read()
try:
    v = json.loads(raw)
except Exception:
    print("unparsable"); raise SystemExit
if not isinstance(v, list) or len(v) != 1:
    print("not-one-element"); raise SystemExit
x = v[0]
if x is None:
    print("null"); raise SystemExit
if isinstance(x, bool) or not isinstance(x, (int, float)) or not math.isfinite(x):
    print("not-a-number"); raise SystemExit
print(repr(float(x)))
PY

# label | lon | lat | expected: "value" or "null"
CASES=(
    "臺灣 玉山|120.957283|23.47|value"
    "臺灣 台北101|121.5645|25.0339|value"
    "臺灣 高雄|120.3|22.63|value"
    "澎湖 馬公|119.5667|23.5695|value"
    "金門 太武山|118.3168|24.4326|value"
    "金門 烈嶼|118.2460|24.4350|value"
    "基隆嶼|121.7833|25.1917|value"
    "蘭嶼|121.5583|22.0417|value"
    "小琉球|120.3650|22.3420|value"
    # Dropped by the 2025 release; see README.md and issue #2.
    "綠島|121.4900|22.6575|null"
    "龜山島|121.9557|24.8386|null"
    # Never covered by any MOI 20 m release.
    "馬祖 南竿|119.9297|26.1508|null"
    "東引|120.4917|26.3667|null"
    "彭佳嶼|122.0783|25.6283|null"
    "棉花嶼|122.1067|25.4867|null"
    "花瓶嶼|122.0833|25.4333|null"
    "烏坵|119.4500|24.9833|null"
    "東沙島|116.7167|20.7000|null"
    "太平島|114.3655|10.3772|null"
)

CID=$(docker run -d -e PORT=8080 "$IMAGE")
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT

# The address is not assigned the instant `docker run -d` returns, so it has
# to be re-read while waiting rather than captured once up front.
IP=""
for _ in $(seq 60); do
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CID" 2>/dev/null || true)
    if [ -n "$IP" ] && docker run --rm curlimages/curl:latest -s -m 2 -o /dev/null \
            -XPOST --data '[[121.0,23.5]]' "http://$IP:8080/v1/elevations" 2>/dev/null; then
        break
    fi
    if [ -z "$(docker ps -q --filter id="$CID")" ]; then
        echo "container exited during startup:" >&2
        docker logs "$CID" >&2 || true
        exit 1
    fi
    sleep 1
done
if [ -z "$IP" ]; then
    echo "could not reach the container" >&2
    exit 1
fi

fail=0
for case in "${CASES[@]}"; do
    IFS='|' read -r label lon lat expect <<< "$case"
    out=$(docker run --rm curlimages/curl:latest -sS -m 30 -w $'\n%{http_code}' \
        -XPOST --data "[[$lon,$lat]]" "http://$IP:8080/v1/elevations" 2>/dev/null || true)
    code=$(printf '%s' "$out" | tail -n1)
    got=$(printf '%s' "$out" | sed '$d' | python3 -c "$PARSE")

    why=""
    if [ "$code" != "200" ]; then
        why="HTTP $code"
    elif [ "$expect" = "null" ]; then
        [ "$got" = "null" ] || why="expected null"
    else
        case "$got" in
            null|unparsable|not-one-element|not-a-number) why="expected an elevation" ;;
            *) awk -v v="$got" -v lo="$MIN_M" -v hi="$MAX_M" \
                   'BEGIN{exit !(v>=lo && v<=hi)}' || why="outside ${MIN_M}..${MAX_M} m" ;;
        esac
    fi

    if [ -n "$why" ]; then
        printf '  FAIL %-16s %-22s %s\n' "$label" "$got" "$why"
        fail=1
    else
        printf '  ok   %-16s %s\n' "$label" "$got"
    fi
done

echo
if [ "$fail" -ne 0 ]; then
    echo "Coverage does not match README.md."
    exit 1
fi
echo "Coverage matches README.md."
