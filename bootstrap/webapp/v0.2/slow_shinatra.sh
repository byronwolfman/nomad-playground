#!/usr/bin/env sh

echo "Starting up..."
for i in $(seq 3 -1 1) ; do
  echo "Ready in ${i}..."
  sleep 5
done

echo "Ready"

RESPONSE="HTTP/1.1 200 OK\r\nConnection: keep-alive\r\n\r\nOK 0.2\r\n"
while { echo -en "$RESPONSE"; } | nc -l -p 8080; do
  echo "================================================"
done
