#!/bin/bash
export ENCRYPTED=true
export DISABLE_STAGE3=true
export ARCHITECT_BRANCH=encrypted-disk

curl 192.168.122.1:8000/architect.sh > architect.sh