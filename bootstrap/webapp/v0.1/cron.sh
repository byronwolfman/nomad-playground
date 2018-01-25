#!/usr/bin/env sh

# Pretend to run a task
echo 'Executing 0.1...'
for i in $(seq 1 30) ; do
  echo "Doing some work..."
  sleep 5
done
echo 'Done!'
exit 0
