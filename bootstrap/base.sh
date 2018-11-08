#!/bin/bash

# Install base dependencies
yum install -y \
  ansible \
  bind-utils \
  epel-release \
  unzip

# Install pip
yum install -y python2-pip --enablerepo=epel

# Install docker-py for Ansible
pip install docker-py
