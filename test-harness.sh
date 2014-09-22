#!/bin/sh

if [ $# -ne 4 ]; then
	echo "Usage: $0 host host-precise jpegpfx out.csv"                >&2
	echo "e.g.: test-harness.sh tabinet-wifi tabinet foo all-foo.csv" >&2
	exit 127
fi

HOST=${1:-localhost}; shift
HOSTPRECISE=${1:-localhost}; shift
JPEG=${1:-fox}; shift
PORT=8099
REALURL="http://${HOST}:${PORT}/${JPEG}.jpg"
PRECISEURL="http://${HOSTPRECISE}:${PORT}/${JPEG}.jpg"
OUTCSV=${1:-out.csv}; shift

# uses SHA-1
shafile () {
	FI=$1; shift
	shasum -a1 "$FI" | cut -d' ' -f1
	return $?
}

filesize () {
	FI=$1; shift
	stat -c '%s' "$FI"
	return $?
}

# SHA-1 of target file
SHA1GOOD=$(shafile htdocs/"${JPEG}".jpg)

BITRATE=55 # Mbps

WARMUPTRIALS=2
NRUNS=10

do_run_precise_tcp () {
	JPGF="${JPEG}-precise-tcp.jpg"
	rm -f "$JPGF"
	TIMINGS=$(
		echo "print %{time_total} - %{time_starttransfer}\\\\n" | \
			curl -s -w '@-' -o "$JPGF" "$REALURL"
		)
	TIMINGP=$(perl -e "$TIMINGS")
	SHA1NOW=$(shafile "$JPGF")
	SIZENOW=$(filesize "$JPGF")
	CSVLINE="${BITRATE},tcp,F,${SIZENOW},${TIMINGP},${SHA1GOOD},${SHA1NOW}"
	echo "$CSVLINE"
	test "$SHA1GOOD" = "$SHA1NOW"
	return $?
}

do_run_precise_sap () {
	JPGF="${JPEG}-precise-sap.jpg"
	rm -f "$JPGF"
	./libsap/examples/recvfile/recvfile \
		"htdocs/${JPEG}.jpg" "$JPGF" 2>"${JPGF}.log" &
	curl -s -o "${JPGF}.deleteme" -H 'X-SAP-Approx: image/jpeg' -H 'X-SAP-Force-Precise: True' "$REALURL"
	wait # best command ever
	TIME_US=$(tail -1 "${JPGF}.log" | grep -o '[0-9]\+')
	if [ -z "$TIME_US" ]; then return 1; fi
	TIME_S=$(perl -e "print $TIME_US / 1e6")
	SHA1NOW=$(shafile "$JPGF")
	SIZENOW=$(filesize "$JPGF")
	CSVLINE="${BITRATE},sap,F,${SIZENOW},${TIME_S},${SHA1GOOD},${SHA1NOW}"
	echo "$CSVLINE"
	test "$SHA1GOOD" = "$SHA1NOW"
	return 0
}

do_run_approx_sap () {
	JPGF="${JPEG}-approx-sap.jpg"
	rm -f "$JPGF"
	./libsap/examples/recvfile/recvfile \
		"htdocs/${JPEG}.jpg" "$JPGF" 2>"${JPGF}.log" &
	curl -s -o "${JPGF}.deleteme" -H 'X-SAP-Approx: image/jpeg' "$REALURL"
	wait # best command ever
	TIME_US=$(tail -1 "${JPGF}.log" | grep -o '[0-9]\+')
	echo "got TIME_US=${TIME_US}" >&2
	if [ -z "$TIME_US" ]; then return 1; fi
	TIME_S=$(perl -e "print $TIME_US / 1e6")
	SHA1NOW=$(shafile "$JPGF")
	SIZENOW=$(filesize "$JPGF")
	CSVLINE="${BITRATE},sap,T,${SIZENOW},${TIME_S},${SHA1GOOD},${SHA1NOW}"
	echo "$CSVLINE"
	return 0
}

# warm the cache
for x in $(seq 1 ${WARMUPTRIALS}); do
	echo -n "warming cache, trial $x... "
	curl --fail --silent -o /dev/null "$PRECISEURL" && echo "done."
done

##### ==================================================================== #####

# prep: rxmode, bitrate
sudo /mnt/sap/util/setrate.sh "${BITRATE}M"
ssh "$HOSTPRECISE" sudo /mnt/sap/util/setrate.sh "${BITRATE}M"

echo "bitrate,protocol,is_approx,nbytes,xfer_time_s,sha1sum_good,sha1sum_current" > "$OUTCSV"

# collect precise data
sudo /mnt/sap/util/rxmode-normal.sh
ssh "$HOSTPRECISE" sudo /mnt/sap/util/rxmode-normal.sh
for x in `seq 1 ${NRUNS}`; do
	echo -n "doing precise TCP run, trial $x... "
	do_run_precise_tcp >> "$OUTCSV"
	if [ $? -eq 0 ]; then echo "done."; else echo "ERROR!"; fi
	sleep 1
done

sudo /mnt/sap/util/rxmode-normal.sh
ssh "$HOSTPRECISE" sudo /mnt/sap/util/rxmode-normal.sh
for x in `seq 1 ${NRUNS}`; do
	echo -n "doing precise SAP run, trial $x... "
	do_run_precise_sap >> "$OUTCSV"
	if [ $? -eq 0 ]; then echo "done."; else echo "ERROR!"; fi
	sleep 1
done

# collect approx-sap data
sudo /mnt/sap/util/rxmode-badfcs.sh
ssh "$HOSTPRECISE" sudo /mnt/sap/util/rxmode-badfcs.sh
for x in `seq 1 ${NRUNS}`; do
	echo -n "doing approx SAP run, trial $x... "
	do_run_approx_sap >> "$OUTCSV"
	if [ $? -eq 0 ]; then echo "done."; else echo "ERROR!"; fi
	sleep 1
done
