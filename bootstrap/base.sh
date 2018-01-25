#!/bin/bash

# Install base dependencies
yum install -y \
  ansible-2.4.1.0 \
  bind-utils \
  epel-release \
  unzip

# Install pip
yum install -y python2-pip --enablerepo=epel

# Install docker-py for Ansible
pip install docker-py
