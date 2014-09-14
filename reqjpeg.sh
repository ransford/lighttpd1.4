#!/bin/sh

HOST=${1:-localhost}

test -f ./libsap/examples/stream/recvfile || make -C libsap || exit 1

./libsap/examples/stream/recvfile htdocs/foo.jpg foo-tmp.jpg &

curl -v -O -H 'X-SAP-Approx: image/jpeg, image/tiff' \
	"http://${HOST}:8099/fox.jpg"

sha1sum htdocs/fox.jpg fox-tmp.jpg
