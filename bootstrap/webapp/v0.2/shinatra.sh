#!/usr/bin/env sh
RESPONSE="HTTP/1.1 200 OK\r\nConnection: keep-alive\r\n\r\nOK 0.2\r\n"
while { echo -en "$RESPONSE"; } | nc -l -p 8080; do
  echo "================================================"
done
