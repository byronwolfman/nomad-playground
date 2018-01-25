#!/usr/bin/env sh

RESPONSE="HTTP/1.1 200 OK\r\nConnection: keep-alive\r\n\r\nOK 0.3\r\n"
for i in $(seq 1 20) ; do
  { echo -en "$RESPONSE"; } | nc -l -p 8080
  echo "================================================"
done

BAD_RESPONSE="HTTP/1.1 500 Internal Server Error\r\nConnection: keep-alive\r\n\r\nError 0.3\r\n"
while { echo -en "$BAD_RESPONSE"; } | nc -l -p 8080; do
  echo "================================================"
done
