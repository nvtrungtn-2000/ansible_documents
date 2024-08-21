#!/bin/bash
ansible-playbook nrpe_install_and_register.yml -i inventory --ask-vault-pass
