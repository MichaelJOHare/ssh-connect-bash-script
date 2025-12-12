#!/bin/bash
# prompt functions for addhost.sh

_add_or_list_menu() {
  local config_file="$1"
  local selection=""

  while true; do
    clear
    printf '\n%s\n\n' "-----------------ADD OR LIST HOSTS--------------------"
    printf '1) %s or edit %s\n' "${CLR_MAGENTA}Add${CLR_RESET}" "${CLR_GREEN}hosts${CLR_RESET}"
    printf '2) %s existing %s\n' "${CLR_MAGENTA}List${CLR_RESET}" "${CLR_GREEN}hosts${CLR_RESET}"
    printf '\n%s' "Enter selection (or ${CLR_RED}E${CLR_RESET} to exit) [${CLR_GREEN}1${CLR_RESET}]: "
    read -r selection
    case "$selection" in
      ''|1)
        break
        ;;
      2)
        mapfile -t hosts < <(_load_host_aliases "$config_file" | sort -f)
        if [ ${#hosts[@]} -eq 0 ]; then
          printf 'No hosts found in %s\n' "$config_file" >&2
          return 1
        fi
        printf 'Listing existing hosts in %s:\n\n' "${CLR_MAGENTA}$config_file${CLR_RESET}"
        for idx in "${!hosts[@]}"; do
          local host_display
          host_display="$(_format_host_display "${hosts[idx]}")"
          printf '%d) %s\n' $((idx+1)) "$host_display"
        done

        printf '\nPress Enter to return to menu...' # change this to allow selecting a host to edit/remove/view details
        read -r _
        ;;
      [Ee])
        clear
        return 0
        ;;
      *)
        _clear_prev_input
        printf '%s\n' "${CLR_RED}Invalid selection.${CLR_RESET}"
        sleep 1
        ;;
    esac
  done
}

# prompts for a unique host alias (nickname with optional group)
_prompt_nickname() {
  local config_file1="$1"
  local -n _alias_ref="$2"
  local -n _last_msg_ref="$3"

  printf 'Enter unique %s for the host (or %s to exit): ' "${CLR_GREEN}nickname${CLR_RESET}" "${CLR_RED}E${CLR_RESET}"
  local host_input=""
  read -r host_input
  if [[ "$host_input" =~ ^[Ee]$ ]]; then
    return 2
  fi

  local nickname=""
  nickname="$(_normalize_identifier "$host_input" upper)"
  local status=$?
  if [[ $status -ne 0 ]]; then
    if [[ $status -eq 1 ]]; then
      _last_msg_ref="Nickname is required."
    else
      _last_msg_ref="Nicknames must consist of letters and/or numbers."
    fi
    return 1
  fi

  local -a matching_aliases=()
  mapfile -t matching_aliases < <(_find_aliases_for_nickname "$nickname" "$config_file1")

  # if matches found, prompt to select which to edit
  if [ "${#matching_aliases[@]}" -gt 0 ]; then
    if ! _select_existing_alias "$nickname" matching_aliases _alias_ref _last_msg_ref; then
      return 1
    fi
    return 0
  fi

  local group_name=""
  if ! _prompt_group_name group_name _last_msg_ref; then
    return 1
  fi

  local resolved_alias="$nickname"
  if [[ -n "$group_name" ]]; then
    resolved_alias="${group_name}${GROUP_DELIMITER}${nickname}"
  fi

  _alias_ref="$resolved_alias"
  return 0
}

_prompt_hostname() {
  local current="$1"
  local -n _hostname_ref="$2"
  local -n _last_msg_ref1="$3"

  printf 'Enter hostname or IP'
  if [ -n "$current" ]; then
    printf ' [%s]' "${CLR_GREEN}$current${CLR_RESET}"
  fi
  printf ' (or %s to cancel): ' "${CLR_RED}E${CLR_RESET}"
  local hostname_input=""
  read -r hostname_input
  if [[ "$hostname_input" =~ ^[Ee]$ ]]; then
    _last_msg_ref1="Hostname entry cancelled. Any changes to host were not saved."
    return 1
  fi
  if [[ -n "$hostname_input" ]]; then
    _hostname_ref="$hostname_input"
  elif [[ -n "$current" ]]; then
    _hostname_ref="$current"
  else
    _last_msg_ref1="Hostname/IP is required."
    return 1
  fi
  return 0
}

_prompt_group_name() {
  local -n _group_ref="$1"
  local -n _last_msg_ref2="$2"
  local belongs_group=""
  local group_input=""
  local normalized=""

  printf 'Is this host part of a %s? (y/N): ' "${CLR_ORANGE}group${CLR_RESET}"
  read -r belongs_group
  if [[ ! "$belongs_group" =~ ^[Yy]$ ]]; then
    _group_ref=""
    return 0
  fi

  local prompt="Enter a group name, use only letters and/or numbers "
  prompt+="(${CLR_GREEN}Enter${CLR_RESET} to skip, ${CLR_RED}E${CLR_RESET} to cancel): "
  while true; do
    printf '%s' "$prompt"
    read -r group_input
    if [[ "$group_input" =~ ^[Ee]$ ]]; then
      _last_msg_ref2="Group selection cancelled. Any changes to host were not saved."
      return 1
    fi

    if ! normalized="$(_normalize_identifier "$group_input" lower 1)"; then
      printf '%s\n' "${CLR_RED}Group names must consist of letters and/or numbers.${CLR_RESET}"
      continue
    fi
    _group_ref="$normalized"
    return 0
  done
}

_prompt_port() {
  local current="${1:-22}"
  local -n _port_ref="$2"
  local -n _last_msg_ref3="$3"

  printf 'Enter port [%s] (or %s to cancel): ' "${CLR_GREEN}${current}${CLR_RESET}" "${CLR_RED}E${CLR_RESET}"
  local port_input=""
  read -r port_input
  if [[ "$port_input" =~ ^[Ee]$ ]]; then
    _last_msg_ref3="Port entry cancelled. Any changes to host were not saved."
    return 1
  fi
  if [[ -n "$port_input" ]]; then
    _port_ref="$port_input"
  else
    _port_ref="$current"
  fi
  if [[ -z "$_port_ref" ]]; then
    _port_ref="22"
  fi
  return 0
}

_prompt_configure_algorithms() {
  local host_alias="$1"
  local -n _hostkey_ref="$2"
  local -n _kex_ref="$3"
  local -n _macs_ref="$4"
  local -n _last_msg_ref4="$5"
  local algo_choice=""

  while true; do
    local algo_prompt1="Configure algorithms -- ${CLR_YELLOW}H${CLR_RESET})ostKeyAlgorithms, "
    algo_prompt1+="${CLR_YELLOW}K${CLR_RESET})exAlgorithms, ${CLR_YELLOW}M${CLR_RESET})ACs"
    algo_prompt1+=" (e.g. input ${CLR_YELLOW}HKM${CLR_RESET} to configure all)"
    local algo_prompt2="Press ${CLR_GREEN}Enter${CLR_RESET} to keep current algorithm settings "
    algo_prompt2+="(${CLR_RED}E${CLR_RESET} to cancel, ${CLR_MAGENTA}?${CLR_RESET} to list current settings): "
    printf '%s\n%s' "$algo_prompt1" "$algo_prompt2"
    read -r algo_choice

    if [[ "$algo_choice" =~ ^[Ee]$ ]]; then
      _last_msg_ref4="Algorithm configuration cancelled. Any changes to host were not saved."
      return 1
    fi

    if [[ "$algo_choice" == "?" ]]; then
      printf '\nCurrent algorithm settings for host %s:\n' "${CLR_GREEN}$host_alias${CLR_RESET}"
      _format_algo_display "$_hostkey_ref" "HostKeyAlgorithms"
      _format_algo_display "$_kex_ref" "KexAlgorithms"
      _format_algo_display "$_macs_ref" "MACs"
      printf '\nPress %s to continue...' "${CLR_GREEN}Enter${CLR_RESET}"
      read -r
      printf '\n'
      continue
    fi

    if [[ -z "$algo_choice" ]]; then
      return 0
    fi

    algo_choice="${algo_choice^^}"
    algo_choice="${algo_choice//[^HKM]/}"
    if [[ -z "$algo_choice" ]]; then
      printf '%s\n' "${CLR_RED}Enter a combination of H, K, or M.${CLR_RESET}"
      continue
    fi
    break
  done

  if [[ "$algo_choice" == *"H"* ]]; then
    local hostkey_input
    printf 'HostKeyAlgorithms%s' "${_hostkey_ref:+ [$_hostkey_ref]}"
    read -r -p " (blank keeps current, '-' removes): " hostkey_input
    if [[ "$hostkey_input" == '-' ]]; then
      _hostkey_ref=""
    elif [[ -n "$hostkey_input" ]]; then
      _hostkey_ref="+$hostkey_input"
    fi
  fi

  if [[ "$algo_choice" == *"K"* ]]; then
    local kex_input
    printf 'KexAlgorithms%s' "${_kex_ref:+ [$_kex_ref]}"
    read -r -p " (blank keeps current, '-' removes): " kex_input
    if [[ "$kex_input" == '-' ]]; then
      _kex_ref=""
    elif [[ -n "$kex_input" ]]; then
      _kex_ref="+$kex_input"
    fi
  fi

  if [[ "$algo_choice" == *"M"* ]]; then
    local macs_input
    printf 'MACs%s' "${_macs_ref:+ [$_macs_ref]}"
    read -r -p " (blank keeps current, '-' removes): " macs_input
    if [[ "$macs_input" == '-' ]]; then
      _macs_ref=""
    elif [[ -n "$macs_input" ]]; then
      _macs_ref="+$macs_input"
    fi
  fi

  return 0
}

# prompt user to select which existing alias to edit
_select_existing_alias() {
  local nickname="$1"
  local -n _matches_ref="$2"
  local -n _alias_ref1="$3"
  local -n _last_msg_ref5="$4"
  local resolved_alias=""

  # if multiple matches, prompt user to select which one
  if [ "${#_matches_ref[@]}" -gt 1 ]; then
    printf '\nNickname %s exists in multiple host entries:\n' "${CLR_GREEN}${nickname}${CLR_RESET}"
    for idx in "${!_matches_ref[@]}"; do
      printf '  %d) %s\n' $((idx+1)) "${CLR_GREEN}${_matches_ref[idx]}${CLR_RESET}"
    done
    local alias_choice=""
    while true; do
      printf 'Select entry to edit %s to cancel: ' "(1-${#_matches_ref[@]}) or ${CLR_RED}E${CLR_RESET}"
      read -r alias_choice
      if [[ "$alias_choice" =~ ^[Ee]$ ]]; then
        _last_msg_ref5="Selection cancelled."
        return 1
      fi
      if [[ "$alias_choice" =~ ^[0-9]+$ ]] && [ "$alias_choice" -ge 1 ] && [ "$alias_choice" -le "${#_matches_ref[@]}" ]; then
        resolved_alias="${_matches_ref[$((alias_choice-1))]}"
        break
      fi
      _clear_prev_input
      printf '%s\n' "${CLR_RED}Enter a valid selection.${CLR_RESET}"
    done
  else
    # single match, use it
    resolved_alias="${_matches_ref[0]}"
  fi

  # if editing existing alias, grab group name if any
  local group_name=""
  if [[ "$resolved_alias" == *"$GROUP_DELIMITER"* ]]; then
    group_name="${resolved_alias%%"$GROUP_DELIMITER"*}"
  fi

  local host_display="${CLR_GREEN}${nickname}${CLR_RESET}"
  if [[ -n "$group_name" ]]; then
    host_display="${CLR_ORANGE}${group_name^^} ${host_display}"
  fi

  printf '\nHost %s already exists.\n' "$host_display"
  local edit_choice=""
  read -r -p "Edit this host? (Y/n): " edit_choice
  if [[ "$edit_choice" =~ ^[Nn]$ ]]; then
    _last_msg_ref5="Use a different nickname or confirm edit, each entry must have a unique nickname."
    return 1
  fi

  _alias_ref1="$resolved_alias"
  return 0
}

# prompt to change alias (nickname and/or group) when editing existing host
_prompt_alias_edit() {
  local current_alias="$1"
  local config_file2="$2"
  local -n _alias_ref2="$3"
  local -n _last_msg_ref6="$4"
  local current_group=""
  local current_nickname="$current_alias"

  if [[ "$current_alias" == *"$GROUP_DELIMITER"* ]]; then
    current_group="${current_alias%%"$GROUP_DELIMITER"*}"
    current_nickname="${current_alias#*"$GROUP_DELIMITER"}"
  fi

  local host_display="${CLR_GREEN}${current_nickname}${CLR_RESET}"
  if [[ -n "$current_group" ]]; then
    host_display="${CLR_ORANGE}${current_group^^}${CLR_RESET} ${host_display}"
  fi

  printf '\nEditing existing host %s\n' "$host_display"
  local update_choice=""
  read -r -p "Change nickname or group? (y/N): " update_choice
  if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
    _alias_ref2="$current_alias"
    return 0
  fi

  local new_nickname="$current_nickname"
  while true; do
    local nickname_prompt="Enter new nickname [${CLR_GREEN}${current_nickname}${CLR_RESET}] "
    nickname_prompt+="(${CLR_GREEN}Enter${CLR_RESET} keeps current, ${CLR_RED}E${CLR_RESET} to cancel): "
    printf '%s' "$nickname_prompt"
    local nickname_input=""
    read -r nickname_input

    if [[ "$nickname_input" =~ ^[Ee]$ ]]; then
      _last_msg_ref6="Nickname edit cancelled. Any changes to host were not saved."
      return 1
    fi
    if [[ -z "$nickname_input" ]]; then
      break
    fi

    local normalized=""
    normalized="$(_normalize_identifier "$nickname_input" upper)"
    local status=$?
    if [[ $status -eq 0 ]]; then
      new_nickname="$normalized"
      break
    fi
    if [[ $status -eq 1 ]]; then
      printf '%s\n' "${CLR_RED}Nickname is required.${CLR_RESET}"
    else
      printf '%s\n' "${CLR_RED}Nicknames must consist of letters and/or numbers.${CLR_RESET}"
    fi
  done

  local new_group="$current_group"
  while true; do
    local group_label="none"
    if [[ -n "$current_group" ]]; then
      group_label="${current_group^^}"
    fi

    local group_prompt="Enter new group name [${CLR_ORANGE}${group_label}${CLR_RESET}] (${CLR_GREEN}Enter${CLR_RESET} keeps current,"
    group_prompt+=" ${CLR_MAGENTA}-${CLR_RESET} removes, ${CLR_RED}E${CLR_RESET} to cancel): "
    printf '%s' "$group_prompt"
    local group_input=""
    read -r group_input

    if [[ "$group_input" =~ ^[Ee]$ ]]; then
      _last_msg_ref6="Group edit cancelled. Any changes to host were not saved."
      return 1
    fi
    if [[ "$group_input" == '-' ]]; then
      new_group=""
      break
    fi
    if [[ -z "$group_input" ]]; then
      break
    fi

    local normalized_group=""
    normalized_group="$(_normalize_identifier "$group_input" lower)"
    local group_status=$?
    if [[ $group_status -eq 0 ]]; then
      new_group="$normalized_group"
      break
    fi
    printf '%s\n' "${CLR_RED}Group names must consist of letters and/or numbers.${CLR_RESET}"
  done

  local new_alias="$new_nickname"
  if [[ -n "$new_group" ]]; then
    new_alias="${new_group}${GROUP_DELIMITER}${new_nickname}"
  fi

  if [[ "$new_alias" != "$current_alias" ]] && _host_entry_exists "$new_alias" "$config_file2"; then
    _last_msg_ref6="Nickname ${new_alias} already exists. Choose a different nickname or group."
    return 1
  fi

  _alias_ref2="$new_alias"
  return 0
}