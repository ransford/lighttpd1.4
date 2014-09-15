#!/bin/sh

HOST=${1:-localhost}

test -f ./libsap/examples/recvfile/recvfile || make -C libsap || exit 1

./libsap/examples/recvfile/recvfile htdocs/fox.jpg fox-tmp.jpg 2>fox.log &

curl -v -O -H 'X-SAP-Approx: image/jpeg, image/tiff' \
	"http://${HOST}:8099/fox.jpg"

sha1sum htdocs/fox.jpg fox-tmp.jpg
