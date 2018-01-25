#!/usr/bin/env sh

clean_exit()
{
  echo 'Got SIGTERM; exiting...'
  exit 0
}

# Docker will send SIGTERM when trying to stop a container
trap clean_exit SIGTERM

# Pretend to poll
while true ; do
  echo 'polling 0.2...'
  sleep 1
done
