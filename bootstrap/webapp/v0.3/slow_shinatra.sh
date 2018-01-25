#!/usr/bin/env sh

echo "Starting up..."
for i in $(seq 3 -1 1) ; do
  echo "Ready in ${i}..."
  sleep 5
done

while true ; do
  echo "Failing..."
  sleep 5
done
