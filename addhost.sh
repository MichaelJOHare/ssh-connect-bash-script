#!/bin/bash
# add ssh sessions to ~/.ssh/config

# add ability to list hosts and remove them
GROUP_DELIMITER='.'
if ! declare -F addhost >/dev/null; then
addhost() {
  # set stty to default aka ON (it is unset in bashrc so that ssh can inherits it being off)
  stty onlcr
  # find ssh config
  local ssh_config="$HOME/.ssh/config"
  _ensure_ssh_config "$ssh_config" || { printf 'Unable to access %s\n' "$ssh_config" >&2; return 1; }

  # store error messages
  local last_msg=""

  # main menu loop
  while true; do
    clear
    printf '\n%s\n\n\n' "-----------------ADD HOST MENU--------------------"

    # list existing groups
    local -a existing_groups=()
    mapfile -t existing_groups < <(_list_config_groups "$ssh_config")
    if [ "${#existing_groups[@]}" -gt 0 ]; then
      printf 'Existing groups: \033[38;5;208m%s\033[0m\n\n' "$(IFS=', '; echo "${existing_groups[*]^^}")"
    fi

    # display last error message if any
    if [ -n "$last_msg" ]; then
      printf '\033[0;31m%s\033[0m\n\n' "$last_msg"
      last_msg=""
    fi

    # get nickname for new host
    printf "Enter unique \033[0;32mnickname\033[0m for the host (or \033[0;31mE\033[0m"
    read -r -p " to exit): " host
    if [[ "$host" =~ ^[Ee]$ ]]; then
      clear
      return 0
    fi

    # sanitize nickname (no spaces or group delimiter)
    host="${host//[[:space:]]/}"
    if [[ "$host" == *"$GROUP_DELIMITER"* ]]; then
      last_msg="Nicknames cannot include $GROUP_DELIMITER; use the group option instead."
      continue
    fi
    if [[ -z "$host" ]]; then
      last_msg="Nickname is required."
      continue
    fi

    # convert nickname to uppercase
    local nickname="${host^^}"
    local -a matching_aliases=()
    mapfile -t matching_aliases < <(_find_aliases_for_nickname "$nickname" "$ssh_config")
    local host_alias=""
    local group_name=""

    # deal with editing host that appears more than once already in ssh config
    if [ "${#matching_aliases[@]}" -gt 0 ]; then
      if [ "${#matching_aliases[@]}" -gt 1 ]; then
        printf '\nNickname \033[0;32m%s\033[0m exists in multiple host entries:\n' "$nickname"
        for idx in "${!matching_aliases[@]}"; do
          printf '  %d) \033[0;32m%s\033[0m\n' $((idx+1)) "${matching_aliases[idx]}" # find better way to differentiate (hostname?)
        done

        # get nickname to edit
        local alias_choice=""
        while true; do
          printf 'Select entry to edit %s or \033[0;31mE\033[0m' "(1-${#matching_aliases[@]})"
          read -r -p " to cancel: " alias_choice
          if [[ "$alias_choice" =~ ^[Ee]$ ]]; then
            host_alias=""
            break
          elif [[ "$alias_choice" =~ ^[0-9]+$ ]] && [ "$alias_choice" -ge 1 ] && [ "$alias_choice" -le "${#matching_aliases[@]}" ]; then
            host_alias="${matching_aliases[$((alias_choice-1))]}"
            break
          else
            _clear_prev_input
            printf '\033[0;31mEnter a valid selection.\033[0m\n'
          fi
        done
        if [[ -z "$host_alias" ]]; then
          last_msg="Selection cancelled."
          continue
        fi
      else
        host_alias="${matching_aliases[0]}"
      fi

      # deal with editing host that appears once already in ssh config
      printf '\nHost \033[0;32m%s\033[0m already exists.\n' "$host_alias"
      read -r -p "Edit this host? (Y/n): " edit_choice
      if [[ "$edit_choice" =~ ^[Nn]$ ]]; then
        last_msg="Use a different nickname or confirm edit."   # should we even be forcing unique nicknames?
        continue
      fi
      if [[ "$host_alias" == *"$GROUP_DELIMITER"* ]]; then
        group_name="${host_alias%%"$GROUP_DELIMITER"*}"
      fi
    else
      local belongs_group="n"    # add E to exit option
      read -r -p "Is this host part of a group? (y/N): " belongs_group
      if [[ "$belongs_group" =~ ^[Yy]$ ]]; then
        read -r -p "Enter group name (letters/numbers): " group_name
        group_name="${group_name//[[:space:]]/}"
        group_name="${group_name,,}"
        if [[ -z "$group_name" || ! "$group_name" =~ ^[a-z0-9]+$ ]]; then
          last_msg="Group names must be letters/numbers."
          continue
        fi
      else
        group_name=""
      fi
      host_alias="$nickname"
      if [[ -n "$group_name" ]]; then
        host_alias="${group_name}${GROUP_DELIMITER}${nickname}"
      fi
    fi

    # initialize host values
    local hostname=""
    local port="22"
    local hostkey=""
    local kex=""
    local macs=""

    # if editing existing host, read current values
    if _host_entry_exists "$host_alias" "$ssh_config"; then
      IFS='|' read -r hostname port hostkey kex macs <<< "$( _read_host_values "$host_alias" "$ssh_config" )"
      [[ -z "$port" ]] && port="22"
    fi

    # get host values from user
    printf 'Enter hostname or IP'
    if [ -n "$hostname" ]; then
      printf ' [\033[0;32m%s\033[0m] (or \033[0;31mE\033[0m' "$hostname"
    fi
    read -r -p " to cancel): " hostname_input
    if [[ "$hostname_input" =~ ^[Ee]$ ]]; then
      last_msg="Hostname entry cancelled."
      continue
    fi
    if [[ -n "$hostname_input" ]]; then
      hostname="$hostname_input"
    fi
    if [[ -z "$hostname" ]]; then
      last_msg="Hostname/IP is required."
      continue
    fi

    # get port from user
    printf 'Enter port [\033[0;32m%s\033[0m]: ' "${port:-22}"
    read -r -p " (or E to cancel): " port_input
    if [[ "$port_input" =~ ^[Ee]$ ]]; then
      last_msg="Port entry cancelled."
      continue
    fi
    if [[ -n "$port_input" ]]; then
      port="$port_input"
    fi
    if [[ -z "$port" ]]; then
      port="22"
    fi

    # get current algorithm settings
    local -a algo_flags=()
    [[ -n "$hostkey" ]] && algo_flags+=("H")
    [[ -n "$kex" ]] && algo_flags+=("K")
    [[ -n "$macs" ]] && algo_flags+=("M")
    local algo_current_value="none"
    if [ "${#algo_flags[@]}" -gt 0 ]; then
      algo_current_value="${algo_flags[*]}"
    fi

    # get algorithms to configure from user
    local algo_choice=""                        # make this nicer
    printf 'Configure algorithms (H,K,M e.g. HK) (current: '
    printf '\033[0;32m%s\033[0m' "$algo_current_value"
    printf ')'
    read -r -p " or Enter to skip: " algo_choice
    algo_choice="${algo_choice^^}"
    algo_choice="${algo_choice//[^HKM]/}"

    # edit host key entry if selected
    if [[ -n "$algo_choice" ]]; then
      if [[ "$algo_choice" == *"H"* ]]; then
        local hostkey_input
        printf 'HostKeyAlgorithms%s' "${hostkey:+ [$hostkey]}"
        read -r -p " (blank keeps current, '-' removes): " hostkey_input
        if [[ "$hostkey_input" == '-' ]]; then
          hostkey=""
        elif [[ -n "$hostkey_input" ]]; then
          hostkey="+$hostkey_input"
        fi
      fi

      # edit key exchange entry if selected
      if [[ "$algo_choice" == *"K"* ]]; then
        local kex_input
        printf 'KexAlgorithms%s' "${kex:+ [$kex]}"
        read -r -p " (blank keeps current, '-' removes): " kex_input
        if [[ "$kex_input" == '-' ]]; then
          kex=""
        elif [[ -n "$kex_input" ]]; then
          kex="+$kex_input"
        fi
      fi

      # edit MACs entry if selected
      if [[ "$algo_choice" == *"M"* ]]; then
        local macs_input
        printf 'MACs%s' "${macs:+ [$macs]}"
        read -r -p " (blank keeps current, '-' removes): " macs_input
        if [[ "$macs_input" == '-' ]]; then
          macs=""
        elif [[ -n "$macs_input" ]]; then
          macs="+$macs_input"
        fi
      fi
    fi

    # remove existing host entry and append newly edited one
    _remove_host_entry "$host_alias" "$ssh_config"
    _append_host_entry "$host_alias" "$hostname" "$port" "$ssh_config" "$hostkey" "$kex" "$macs"
    printf 'Saved host \033[0;32m%s\033[0m (%s:%s) to %s\n' "$host_alias" "$hostname" "$port" "$ssh_config"

    local add_more="n"
    read -r -p "Add or edit another host? (y/N): " add_more
    if [[ ! "$add_more" =~ ^[Yy]$ ]]; then
      clear
      return 0
    fi
  done
}
fi
