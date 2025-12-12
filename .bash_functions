#!/bin/bash

VMS_MENU_LIB="$HOME/.local/lib"
VMS_MENU_FILES=(
  "vmsmenu.sh"
  "addhost.sh"
  "shared_utils.sh"
)

for lib_file in "${VMS_MENU_FILES[@]}"; do
  lib_path="${VMS_MENU_LIB}/${lib_file}"
  if [ -r "$lib_path" ]; then
    # shellcheck disable=SC1090
    source "$lib_path"
  fi
done