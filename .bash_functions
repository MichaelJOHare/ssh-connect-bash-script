#!/bin/bash

VMS_LIB_DIR="$HOME/.local/lib"
VMS_HELPERS=(
  "ssh_config_utils.sh"
  "vmsmenu.sh"
  "addhost.sh"
)

for helper in "${VMS_HELPERS[@]}"; do
  helper_path="${VMS_LIB_DIR}/${helper}"
  if [ -r "$helper_path" ]; then
    # shellcheck disable=SC1090
    source "$helper_path"
  fi
done