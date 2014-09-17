#!/bin/sh

HOST=${1:-localhost}
shift
JPEG=${1:-fox}

WARMUPTRIALS=2
NRUNS=10

CSVFILE="runs-precise-${JPEG}.csv"
echo "is_approx,time_starttransfer,time_total,sha1sum_good,sha1sum_current" > "$CSVFILE"

do_run_precise () {
	CF="$1"
	rm -f "${JPEG}-precise.jpg"
	SHA1GOOD=$(shasum -a1 htdocs/"${JPEG}".jpg | cut -d' ' -f1)
	CSVLINE=$(
	echo "F,%{time_starttransfer},%{time_total},${SHA1GOOD}\\\\n" | \
		curl -s -w '@-' -o "${JPEG}-precise.jpg" \
			"http://${HOST}:8099/${JPEG}.jpg"
	)
	SHA1NOW=$(shasum -a1 "${JPEG}-precise.jpg" | cut -d' ' -f1)
	CSVLINE="$CSVLINE,$SHA1NOW"
	if [ -f "$CF" ]; then
		echo "$CSVLINE" >> "$CF"
	fi
	return 0
}

# warm the cache
for x in $(seq 1 ${WARMUPTRIALS}); do
	echo -n "warming cache, trial $x... "
	do_run_precise >/dev/null && echo "done."
done

# collect data
for x in `seq 1 ${NRUNS}`; do
	echo -n "doing run, trial $x... "
	do_run_precise "$CSVFILE"
	echo "done."
done

cat "$CSVFILE"
