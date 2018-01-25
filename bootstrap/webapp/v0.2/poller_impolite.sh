#!/usr/bin/env sh

nope()
{
  echo 'Got SIGTERM; ignoring...'
}

# Docker will send SIGTERM when trying to stop a container
trap nope SIGTERM

# Pretend to poll
while true ; do
  echo 'polling 0.2...'
  sleep 1
done
