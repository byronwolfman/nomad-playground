#!/usr/bin/env sh
RESPONSE="HTTP/1.1 500 Internal Server Error\r\nConnection: keep-alive\r\n\r\nError 0.3\r\n"
while { echo -en "$RESPONSE"; } | nc -l -p 8080; do
  echo "================================================"
done
