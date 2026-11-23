#!/bin/sh
# Profilo web: il nostro sito al posto di quello di default
set -eu
ROOT="$1"
rm -f "${ROOT}/etc/nginx/sites-enabled/default"
ln -sf ../sites-available/golden "${ROOT}/etc/nginx/sites-enabled/golden"
