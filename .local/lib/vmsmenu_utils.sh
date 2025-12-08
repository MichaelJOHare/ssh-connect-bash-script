#!/bin/bash
# utility functions for vmsmenu


_render_menu() {
  local title="$1"
  local subtitle="$2"
  local -n labels_ref="$3"
  local message="$4"
  local types_name="$5"
  local use_types=0
  local format_title="------------------------$title MENU------------------------"

  # check if types array is provided for main menu
  if [[ -n "$types_name" ]]; then
    local -n types_ref="$types_name"
    use_types=1
  fi

  # display menu title and subtitle
  clear
  printf '\n%s\n\n' "$format_title"
  if [[ -n "$subtitle" ]]; then
    printf '%s\n\n' "$subtitle"
  fi

  # if type is group, color orange; if host, color green
  for idx in "${!labels_ref[@]}"; do
    local entry_type=""
    if (( use_types )); then
      entry_type="${types_ref[idx]}"
    fi
    if [[ "$entry_type" == "group" ]]; then
      printf "%d) %s \n" $((idx+1)) "${CLR_ORANGE}${labels_ref[idx]} CLUSTER${CLR_RESET}"
    else
      printf "%d) %s\n" $((idx+1)) "${CLR_GREEN}${labels_ref[idx]}${CLR_RESET}"
    fi
  done

  # display message if any
  if [[ -n "$message" ]]; then
    printf '\n%s\n' "${CLR_RED}$message${CLR_RESET}"
  fi
}

_prompt_selection() {
  local prompt_text="$1"
  local max="$2"
  local allow_back="$3"
  local selection

  read -r -p "$prompt_text" selection

  if [[ "$selection" =~ ^[Ee]$ ]]; then
    printf 'EXIT'
    return 0
  fi

  if [[ "$allow_back" -eq 1 ]] && [[ "$selection" =~ ^[Bb]$ ]]; then
    printf 'BACK'
    return 0
  fi

  if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$max" ]; then
    printf '%d' "$selection"
    return 0
  fi

  printf 'INVALID'
}

_ssh_connect() {
  local host="$1"
  local host_display
  local user
  printf '%s as: ' "${CLR_MAGENTA}login${CLR_RESET}"
  read -r user
  if [[ -z "$user" ]]; then
    return 2
  fi

  host_display="$(_format_host_display "$host")"

  clear
  printf 'Connecting to %s as %s...\n' "$host_display" "${CLR_MAGENTA}$user${CLR_RESET}"
  printf '\033]0;%s\007' "$user@$host"
  if ! ssh "${user}@${host}"; then       # set ConnectTimeout, add visual for long waits?
    printf '\033]0;%s\007' "VMS MENU"    # if ssh fails, prompt to try telnet?
    printf 'SSH connection to %s failed. Returning to menu in 5 seconds...\n' "$host_display"
    sleep 5
    return 1
  fi
  printf '\033]0;%s\007' "VMS MENU"
  return 0
}

_telnet_connect() {
  local host="$1"
  local config_file="$2"
  local host_display
  local entry hostname port

  # get hostname/port since telnet needs them directly
  entry="$(_read_host_values "$host" "$config_file")"
  IFS='|' read -r hostname port _ <<< "$entry"

  if [[ -z "$hostname" ]]; then
    return 3
  fi

  host_display="$(_format_host_display "$host")"

  clear
  printf 'Connecting to %s via telnet...\n' "$host_display"
  printf '\033]0;%s\007' "telnet:$host"
  if ! telnet "$hostname" "${port:-23}"; then
    printf '\033]0;%s\007' "VMS MENU"
    printf 'Telnet connection to %s failed. Returning to menu in 5 seconds...\n' "$host_display"
    sleep 5
    return 1
  fi
  printf '\033]0;%s\007' "VMS MENU"
  return 0
}

_attempt_connection() {
  local host_label="$1"
  local transport="$2"
  local connect_fn="$3"
  local config_file="$4"
  local msg_target="$5"
  local -n _msg_ref="$msg_target"

  "$connect_fn" "$host_label" "$config_file"
  local connect_result=$?
  if [ $connect_result -eq 0 ]; then
    _msg_ref=""
    return 0
  fi

  if [ "$transport" = "ssh" ] && [ $connect_result -eq 2 ]; then
    _msg_ref="Error: username required"
    return 1
  fi

  if [ "$transport" = "telnet" ] && [ $connect_result -eq 3 ]; then
    printf -v _msg_ref 'No telnet hostname/IP configured for %s%s%s\n%sNote%s: ~/.telnet/config should have an empty newline at the end of the file.' \
      "$CLR_GREEN" "$host_label" "$CLR_RESET" "$CLR_YELLOW" "$CLR_RESET"
    return 1
  fi

  _msg_ref="Connection to $host_label failed — returned to menu"
  return 1
}