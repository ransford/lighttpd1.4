#!/bin/sh

if [ $# -ne 6 ]; then
	echo "Usage: $0 host host-precise jpegpfx distance(m) bitrate(Mbps) nruns" >&2
	echo " e.g.: $0 tabinet-wifi tabinet foo 8 54 10"     >&2
	exit 127
fi

HOST=${1:-localhost}; shift
HOSTPRECISE=${1:-localhost}; shift
JPEG=${1:-fox}; shift
DISTANCE=$1; shift
BITRATE=${1:-54}; shift
NRUNS=${1:-10}; shift

PORT=8099
REALURL="http://${HOST}:${PORT}/${JPEG}.jpg"
PRECISEURL="http://${HOSTPRECISE}:${PORT}/${JPEG}.jpg"

GITREV=$(git rev-parse --short HEAD)
MYHOST=$(hostname -s)
OUTCSV="results/${MYHOST}-${HOSTPRECISE}-${BITRATE}M-${DISTANCE}m-${NRUNS}trials-${GITREV}.csv"
mkdir -p results

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

colorecho () {
	MSG=$1; shift
	/bin/echo -e "\033[1;37m${MSG}\033[0m"
}

colorechobad () {
	MSG=$1; shift
	/bin/echo -e "\033[1;31m${MSG}\033[0m"
}

# SHA-1 of target file
SHA1GOOD=$(shafile htdocs/"${JPEG}".jpg)

WARMUPTRIALS=2

do_run_precise_tcp () {
	JPGF="${JPEG}-precise-tcp.jpg"
	rm -f "$JPGF"
	TIMINGS=$(
		echo "print %{time_total} - %{time_starttransfer}\\\\n" | \
			curl -# -w '@-' -o "$JPGF" "$REALURL"
		)
	TIMINGP=$(perl -e "$TIMINGS")
	SHA1NOW=$(shafile "$JPGF")
	SIZENOW=$(filesize "$JPGF")
	CSVLINE="${BITRATE},${DISTANCE},TCP,F,${SIZENOW},${TIMINGP},${SHA1GOOD},${SHA1NOW}"
	echo "$CSVLINE"
	test "$SHA1GOOD" = "$SHA1NOW"
	return $?
}

do_run_precise_sap () {
	RUNNUM=$1; shift
	JPGF="${JPEG}-precise-sap.jpg"
	LOGFILE="${JPGF}.log.${RUNNUM}"
	rm -f "$JPGF"
	./libsap/examples/recvfile/recvfile \
		"htdocs/${JPEG}.jpg" "$JPGF" 2>"${LOGFILE}" &
	curl -# -o "${JPGF}.deleteme" -H 'X-SAP-Approx: image/jpeg' -H 'X-SAP-Force-Precise: True' "$REALURL"
	wait # best command ever
	TIME_US=$(tail -1 "${LOGFILE}" | grep 'Elapsed' | grep -o '[0-9]\+')
	if [ -z "$TIME_US" ]; then return 1; fi
	TIME_S=$(perl -e "print $TIME_US / 1e6")
	SHA1NOW=$(shafile "$JPGF")
	SIZENOW=$(filesize "$JPGF")
	CSVLINE="${BITRATE},${DISTANCE},SAP (Precise),F,${SIZENOW},${TIME_S},${SHA1GOOD},${SHA1NOW}"
	echo "$CSVLINE"
	test "$SHA1GOOD" = "$SHA1NOW"
	return 0
}

do_run_approx_sap () {
	RUNNUM=$1; shift
	JPGF="${JPEG}-approx-sap.jpg"
	LOGFILE="${JPGF}.log.${RUNNUM}"
	rm -f "$JPGF"
	./libsap/examples/recvfile/recvfile \
		"htdocs/${JPEG}.jpg" "$JPGF" 2>"${LOGFILE}" &
	curl -# -o "${JPGF}.deleteme" -H 'X-SAP-Approx: image/jpeg' "$REALURL"
	wait # best command ever
	TIME_US=$(tail -1 "${LOGFILE}" | grep 'Elapsed' | grep -o '[0-9]\+')
	echo "got TIME_US=${TIME_US}" >&2
	tail -1 "${LOGFILE}" >&2
	if [ -z "$TIME_US" ]; then return 1; fi
	TIME_S=$(perl -e "print $TIME_US / 1e6")
	SHA1NOW=$(shafile "$JPGF")
	SIZENOW=$(filesize "$JPGF")
	CSVLINE="${BITRATE},${DISTANCE},SAP (Approx),T,${SIZENOW},${TIME_S},${SHA1GOOD},${SHA1NOW}"
	echo "$CSVLINE"
	return 0
}

colorecho "URL of file to fetch: ${REALURL}"
colorecho "URL of file to fetch for cache warming: ${PRECISEURL}"

# warm the cache
for x in $(seq 1 ${WARMUPTRIALS}); do
	colorecho "warming cache, trial $x... "
	curl --fail -# -o /dev/null "$PRECISEURL" && colorecho "done."
done

##### ==================================================================== #####

# prep: rxmode, bitrate
sudo /mnt/sap/util/setrate.sh "${BITRATE}M"
ssh "$HOSTPRECISE" sudo /mnt/sap/util/setrate.sh "${BITRATE}M"

echo "bitrate_mbps,distance_m,protocol,is_approx,nbytes,xfer_time_s,sha1sum_good,sha1sum_current" > "$OUTCSV"

# collect precise data
sudo /mnt/sap/util/rxmode-normal.sh
ssh "$HOSTPRECISE" sudo /mnt/sap/util/rxmode-normal.sh
for x in `seq 1 ${NRUNS}`; do
	colorecho "doing precise TCP run, trial $x... "
	do_run_precise_tcp $x >> "$OUTCSV"
	if [ $? -eq 0 ]; then colorecho "done."; else colorechobad "ERROR!"; fi
	sleep 1
done

sudo /mnt/sap/util/rxmode-normal.sh
ssh "$HOSTPRECISE" sudo /mnt/sap/util/rxmode-normal.sh
for x in `seq 1 ${NRUNS}`; do
	colorecho "doing precise SAP run, trial $x... "
	do_run_precise_sap $x >> "$OUTCSV"
	if [ $? -eq 0 ]; then colorecho "done."; else colorechobad "ERROR!"; fi
	sleep 1
done

# collect approx-sap data
sudo /mnt/sap/util/rxmode-badfcs.sh
ssh "$HOSTPRECISE" sudo /mnt/sap/util/rxmode-badfcs.sh
for x in `seq 1 ${NRUNS}`; do
	colorecho "doing approx SAP run, trial $x... "
	do_run_approx_sap $x >> "$OUTCSV"
	if [ $? -eq 0 ]; then colorecho "done."; else colorechobad "ERROR!"; fi
	sleep 1
done
