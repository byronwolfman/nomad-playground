# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  BASE_DIR = File.dirname(__FILE__)

  config.vm.box = "bento/centos-7.4"
  config.vm.synced_folder '.', '/vagrant'
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "4096"
  end

  config.vm.provision "shell", path: "#{BASE_DIR}/bootstrap/base.sh"
  config.vm.provision "shell", path: "#{BASE_DIR}/bootstrap/playbooks.sh"
end
