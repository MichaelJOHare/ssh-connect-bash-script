#!/bin/bash
# interactive menu to add or edit SSH/telnet sessions to ~/.ssh/config and ~/.telnet/config


# TODO: - let user select host from list to edit/remove/view details
#   low prio - redo return code handling to avoid magic numbers (add named constants)

# shellcheck disable=SC1091
source "$HOME/.local/lib/addhost_utils.sh"
source "$HOME/.local/lib/addhost_prompts.sh"

if ! declare -F addhost >/dev/null; then
addhost() {
  # store error messages
  local last_msg=""

  # choose transport, ssh (default) or telnet
  local transport_key=""
  if ! _select_transport transport_key; then
    clear
    return 0
  fi

  # prepare config file path based on transport choice
  local config_file=""
  local transport_label=""
  if ! _prepare_transport_config "$transport_key" transport_label config_file; then
    printf 'Unable to access %s config file: %s\n' "$transport_label" "$config_file" >&2
    return 1
  fi

  # initial menu to add or list hosts
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

        printf '\nPress Enter to return to menu...'
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

  # main addhost loop
  while true; do
    clear
    printf '\n%s\n\n\n' "-----------------ADD HOST MENU--------------------"

    # list existing groups
    local -a existing_groups=()
    mapfile -t existing_groups < <(_list_config_groups "$config_file")
    if [ "${#existing_groups[@]}" -gt 0 ]; then
      printf 'Existing groups: %s\n\n' "$(IFS=', '; echo "${CLR_ORANGE}${existing_groups[*]^^}${CLR_RESET}")"
    fi

    # display which config file is being edited
    printf 'Editing %s configuration file: %s\n\n' "$transport_label" "${CLR_MAGENTA}$config_file${CLR_RESET}"

    # display last error message if any
    if [ -n "$last_msg" ]; then
      printf '%s\n\n' "${CLR_RED}${last_msg}${CLR_RESET}"
      last_msg=""
    fi 

    # prompt for nickname and check for existing host entry
    local host_alias=""
    local alias_status=0
    local editing_existing=0
    local original_alias=""
    if _prompt_nickname "$config_file" host_alias last_msg; then
      : # nickname captured successfully
    else
      alias_status=$?
      if [ "$alias_status" -eq 2 ]; then
        clear
        return 0
      fi
      continue
    fi

    if _host_entry_exists "$host_alias" "$config_file"; then
      editing_existing=1
      original_alias="$host_alias"
    fi

    # initialize host values
    local hostname=""
    local port=""
    local hostkey=""
    local kex=""
    local macs=""

    # if editing existing host, read current values
    if (( editing_existing )); then
      IFS='|' read -r hostname port hostkey kex macs <<< "$( _read_host_values "$original_alias" "$config_file" )"
      if ! _prompt_alias_edit "$original_alias" "$config_file" host_alias last_msg; then
        continue
      fi
    fi
  
    if ! _prompt_hostname "$hostname" hostname last_msg; then
      continue
    fi

    if ! _prompt_port "$port" port last_msg; then
      continue
    fi

    if [[ "$transport_key" == "ssh" ]]; then
      if ! _prompt_configure_algorithms "$host_alias" hostkey kex macs last_msg; then
        continue
      fi
    fi

    # if nickname was changed during edit, ensure old entry is removed
    if (( editing_existing )) && [[ "$host_alias" != "$original_alias" ]]; then
      _remove_host_entry "$original_alias" "$config_file"
    fi
    # remove matching host entry if any, and append newly edited or created one
    _remove_host_entry "$host_alias" "$config_file"
    _append_host_entry "$host_alias" "$hostname" "$port" "$config_file" "$hostkey" "$kex" "$macs"

    # format and display success message
    local host_display hostname_display port_display config_file_display
    host_display="$(_format_host_display "$host_alias")"
    hostname_display="${CLR_GREEN}$hostname${CLR_RESET}"
    port_display="${CLR_MAGENTA}$port${CLR_RESET}"
    config_file_display="${CLR_MAGENTA}$config_file${CLR_RESET}"
    printf 'Saved host %s (%s:%s) to %s\n' "$host_display" "$hostname_display" "$port_display" "$config_file_display"

    local add_more="n"
    read -r -p "Add or edit another host? (y/N): " add_more
    if [[ ! "$add_more" =~ ^[Yy]$ ]]; then
      clear
      return 0
    fi
  done
}
fi
