#!/bin/bash
# add ssh sessions to ~/.ssh/config

# TODO: add telnet support using ~/.telnet/config
#       add ability to list hosts and remove them
#       maybe first menu option should ask user listing hosts or create new host
#          - let user select host from list to edit/remove/view details
#       when editing existing host, allow changing nickname and group
#   low prio - cleanup host vs hostalias vs nickname terminology

if ! declare -F addhost >/dev/null; then
addhost() {
  # store error messages
  local last_msg=""

  # find ssh config file or create if missing
  local ssh_config="$HOME/.ssh/config"
  _ensure_config_file "$ssh_config" || {
    printf 'Unable to access ssh config file: %s\n' "$ssh_config" >&2
    return 1
  }

  # find telnet config file or create if missing
  local telnet_config="$HOME/.telnet/config"
  _ensure_config_file "$telnet_config" || { 
    printf 'Unable to access telnet config file: %s\n' "$telnet_config" >&2; 
    return 1; 
  }

  # main menu loop
  while true; do
    clear
    printf '\n%s\n\n\n' "-----------------ADD HOST MENU--------------------"

    # list existing groups
    local -a existing_groups=()
    mapfile -t existing_groups < <(_list_config_groups "$ssh_config")
    if [ "${#existing_groups[@]}" -gt 0 ]; then
      printf 'Existing groups: %s\n\n' "$(IFS=', '; echo "${CLR_ORANGE}${existing_groups[*]^^}${CLR_RESET}")"
    fi

    # display last error message if any
    if [ -n "$last_msg" ]; then
      printf '%s\n\n' "${CLR_RED}${last_msg}${CLR_RESET}"
      last_msg=""
    fi

    # get nickname for new host
    printf 'Enter unique %s for the host (or %s to exit): ' "${CLR_GREEN}nickname${CLR_RESET}" "${CLR_RED}E${CLR_RESET}"
    read -r host
    if [[ "$host" =~ ^[Ee]$ ]]; then
      clear
      return 0
    fi

    # sanitize nickname (no spaces or group delimiter)  -- add disallow all special chars?
    host="${host//[[:space:]]/}"
    if [[ ! "${host,,}" =~ ^[a-z0-9]+$ ]]; then
      last_msg="Nicknames must consist of letters and/or numbers."
      continue
    fi
    if [[ -z "$host" ]]; then
      last_msg="Nickname is required."
      continue
    fi

    # check for existing aliases with this nickname
    local host_alias=""
    local group_name=""
    local nickname="${host^^}"
    local -a matching_aliases=()
    mapfile -t matching_aliases < <(_find_aliases_for_nickname "$nickname" "$ssh_config")

    # deal with editing non-unique nickname
    if [ "${#matching_aliases[@]}" -gt 0 ]; then

      # if 2+ matching aliases, ask which to edit
      if [ "${#matching_aliases[@]}" -gt 1 ]; then
        printf '\nNickname %s exists in multiple host entries:\n' "${CLR_GREEN}${nickname}${CLR_RESET}"
        for idx in "${!matching_aliases[@]}"; do
          printf '  %d) %s\n' $((idx+1)) "${CLR_GREEN}${matching_aliases[idx]}${CLR_RESET}" # find better way to differentiate
        done                                                                                #  - should show details of one and diff the others
                                                                                            #  - create helper in config_utils to do this?
        # get host entry to edit when 2+ matches
        local alias_choice=""
        while true; do
          printf 'Select entry to edit %s to cancel: ' "(1-${#matching_aliases[@]}) or ${CLR_RED}E${CLR_RESET}"
          read -r alias_choice
          if [[ "$alias_choice" =~ ^[Ee]$ ]]; then
            host_alias=""
            break
          elif [[ "$alias_choice" =~ ^[0-9]+$ ]] && [ "$alias_choice" -ge 1 ] && [ "$alias_choice" -le "${#matching_aliases[@]}" ]; then
            host_alias="${matching_aliases[$((alias_choice-1))]}"
            break
          else
            _clear_prev_input
            printf '%s\n' "${CLR_RED}Enter a valid selection.${CLR_RESET}"
          fi
        done
        if [[ -z "$host_alias" ]]; then
          last_msg="Selection cancelled."
          continue
        fi
      else
        host_alias="${matching_aliases[0]}"
      fi

      # parse group and nickname from existing alias
      if [[ "$host_alias" == *"$GROUP_DELIMITER"* ]]; then
        group_name="${host_alias%%"$GROUP_DELIMITER"*}"
      fi

      # only one other matching alias, ask to edit
      printf '\nHost %s already exists.\n' "${CLR_ORANGE}${group_name^^} ${CLR_GREEN}$nickname${CLR_RESET}"
      read -r -p "Edit this host? (Y/n): " edit_choice
      if [[ "$edit_choice" =~ ^[Nn]$ ]]; then
        last_msg="Use a different nickname or confirm edit, each entry must be unique."
        continue
      fi

    else
      # nickname is unique, ask if part of group
      local belongs_group="n"
      printf 'Is this host part of a %s? (y/N): ' "${CLR_ORANGE}group${CLR_RESET}"
      read -r belongs_group

      # get group name if part of group
      if [[ "$belongs_group" =~ ^[Yy]$ ]]; then
        local group_input=""
        local group_prompt="Enter a group name, use only letters and/or numbers "
        group_prompt+="(${CLR_GREEN}Enter${CLR_RESET} to skip, ${CLR_RED}E${CLR_RESET} to cancel): "
        
        # prompt for valid group name
        while true; do
          printf '%s' "$group_prompt"
          read -r group_input
          if [[ "$group_input" =~ ^[Ee]$ ]]; then
            last_msg="Group selection cancelled. Any changes to host were not saved."
            continue 2
          fi

          # sanitize group name
          group_input="${group_input//[[:space:]]/}"
          group_input="${group_input,,}"

          if [[ -z "$group_input" ]]; then
            group_name=""
            break
          fi
          if [[ "${group_input,,}" =~ ^[a-z0-9]+$ ]]; then
            group_name="${group_input,,}"
            break
          fi
          printf '%s\n' "${CLR_RED}Group names must consist of letters and/or numbers.${CLR_RESET}"
        done
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

    # get hostname or IP from user
    printf 'Enter hostname or IP'
    if [ -n "$hostname" ]; then
      printf ' [%s]' "${CLR_GREEN}$hostname${CLR_RESET}"
    fi
    printf ' (or %s to cancel): ' "${CLR_RED}E${CLR_RESET}"
    read -r hostname_input
    if [[ "$hostname_input" =~ ^[Ee]$ ]]; then
      last_msg="Hostname entry cancelled. Any changes to host were not saved."
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
    printf 'Enter port [%s] (or %s to cancel): ' "${CLR_GREEN}${port:-22}${CLR_RESET}" "${CLR_RED}E${CLR_RESET}"
    read -r port_input
    if [[ "$port_input" =~ ^[Ee]$ ]]; then
      last_msg="Port entry cancelled. Any changes to host were not saved."
      continue
    fi
    if [[ -n "$port_input" ]]; then
      port="$port_input"
    fi
    if [[ -z "$port" ]]; then
      port="22"
    fi

    # get algorithms to configure from user
    local algo_choice=""
    while true; do

      # build algorithm selection prompt
      local algo_prompt1="Configure algorithms -- ${CLR_YELLOW}H${CLR_RESET})ostKeyAlgorithms, "
      algo_prompt1+="${CLR_YELLOW}K${CLR_RESET})exAlgorithms, ${CLR_YELLOW}M${CLR_RESET})ACs"
      algo_prompt1+=" (e.g. input ${CLR_YELLOW}HKM${CLR_RESET} to configure all)"
      local algo_prompt2="${CLR_GREEN}Enter${CLR_RESET} to keep current algorithm settings, "
      algo_prompt2+="${CLR_RED}E${CLR_RESET} to cancel, ${CLR_MAGENTA}?${CLR_RESET} to list current settings: "
      printf '%s\n%s' "$algo_prompt1" "$algo_prompt2"
      read -r algo_choice

      # continue 2 so we go back to main while loop
      if [[ "$algo_choice" =~ ^[Ee]$ ]]; then
        last_msg="Algorithm configuration cancelled. Any changes to host were not saved."
        continue 2
      fi

      # list current settings if requested
      if [[ "$algo_choice" == "?" ]]; then
        printf '\nCurrent algorithm settings for host %s:\n' "${CLR_GREEN}$host_alias${CLR_RESET}"
        _format_algo_display "$hostkey" "HostKeyAlgorithms"
        _format_algo_display "$kex" "KexAlgorithms"
        _format_algo_display "$macs" "MACs"
        printf '\n'
        read -r -p "Press Enter to continue..."
        continue
      fi

      # if enter, keep current settings
      if [[ -z "$algo_choice" ]]; then
        algo_choice=""
        break
      fi

      # sanitize input
      algo_choice="${algo_choice^^}"
      algo_choice="${algo_choice//[^HKM]/}"


      # if nothing left, reprompt
      if [[ -z "$algo_choice" ]]; then
        printf '%s\n' "${CLR_RED}Enter a combination of H, K, or M.${CLR_RESET}"
        continue
      fi
      break
    done

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

    # remove existing host entry if any, and append newly edited/created one
    _remove_host_entry "$host_alias" "$ssh_config"
    _append_host_entry "$host_alias" "$hostname" "$port" "$ssh_config" "$hostkey" "$kex" "$macs"
    printf 'Saved host %s (%s:%s) to %s\n' "${CLR_GREEN}$host_alias${CLR_RESET}" "$hostname" "$port" "$ssh_config"

    local add_more="n"
    read -r -p "Add or edit another host? (y/N): " add_more
    if [[ ! "$add_more" =~ ^[Yy]$ ]]; then
      clear
      return 0
    fi
  done
}
fi
