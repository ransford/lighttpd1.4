#!/bin/sh

HOST=${1:-localhost}

curl -v -O -H 'X-SAP-Approx: image/jpeg, image/tiff' \
	"http://${HOST}:8099/fox.jpg"
