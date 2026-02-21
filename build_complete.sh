#!/bin/bash

# A script for building shimboot.

if [ "$1" == "help" ]; then
  echo "Valid distro options: debian, ubuntu, alpine, arch"
  exit 0
}

# Proceed with build commands depending on the selected distribution.
