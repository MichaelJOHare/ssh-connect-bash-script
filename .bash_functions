#!/bin/bash

VMS_MENU_LIB="$HOME/.local/lib"
VMS_MENU=(
  "vmsmenu.sh"
  "addhost.sh"
)

for helper in "${VMS_MENU[@]}"; do
  helper_path="${VMS_MENU_LIB}/${helper}"
  if [ -r "$helper_path" ]; then
    # shellcheck disable=SC1090
    source "$helper_path"
  fi
done