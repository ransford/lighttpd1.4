#!/bin/sh

HOST=${1:-localhost}
shift
JPEG=${1:-fox}

test -f ./libsap/examples/recvfile/recvfile || make -C libsap || exit 1

./libsap/examples/recvfile/recvfile "htdocs/${JPEG}.jpg" "${JPEG}-tmp.jpg" 2>"${JPEG}.log" &

curl -v -O -H 'X-SAP-Approx: image/jpeg, image/tiff' "http://${HOST}:8099/${JPEG}.jpg"

sha1sum "htdocs/${JPEG}.jpg" "${JPEG}-tmp.jpg"
