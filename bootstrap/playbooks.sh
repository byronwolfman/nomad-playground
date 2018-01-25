#!/bin/bash

execute_playbook() {
  echo "Executing playbook for ${1}..."
  ansible-playbook -c local -i "localhost", "/vagrant/bootstrap/${1}/playbook.yml"
}

execute_playbook docker
execute_playbook consul 
execute_playbook nomad
execute_playbook webapp
