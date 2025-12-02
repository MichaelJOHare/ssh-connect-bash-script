#!/bin/bash
# interactive SSH/telnet launcher based on ~/.ssh/config and ~/.telnet/config entries

# TODO: allow switching transport mode (ssh/telnet) from within the menu
#       separate out the function of main (favorited) hosts and grouped hosts
#         - add ability to favorite hosts (e.g., via a separate favorites file?)
# low prio - clean up use of single vs double quotes in printf statements

if ! declare -F vmsmenu >/dev/null; then
vmsmenu() {
  # store error messages
  local last_msg=""

  # choose transport, ssh (default) or telnet
  local transport_key=""
  if ! _select_transport transport_key "SELECT CONNECTION METHOD"; then
    clear
    return 0
  fi

  # prepare config file path and connect function based on transport choice
  local config_file connect_fn transport_label
  case "$transport_key" in
    telnet)
      transport_label="Telnet"
      config_file="$HOME/.telnet/config"
      connect_fn="_telnet_connect"
      ;;
    *)
      transport_label="SSH"
      config_file="$HOME/.ssh/config"
      connect_fn="_ssh_connect"
      ;;
  esac

  # ensure config file exists, or create if missing
  if ! _ensure_config_file "$config_file"; then
    printf 'Unable to access %s config file: %s\n' "$transport_label" "$config_file" >&2
    return 1
  fi

  # load host aliases from config file
  mapfile -t hosts < <(_load_host_aliases "$config_file")
  if [ ${#hosts[@]} -eq 0 ]; then
    printf 'No hosts found in %s\n' "$config_file" >&2
    return 1
  fi

  # separate hosts into main and grouped
  local main_hosts=()
  local -A group_hosts_map=()
  local -a group_names=()

  # initialize group-hosts map
  local group_entry
  local host_entry
  for h in "${hosts[@]}"; do
    if [[ "$h" == *"$GROUP_DELIMITER"* ]]; then
      group_entry="${h%%"$GROUP_DELIMITER"*}"
      host_entry="${h#*"$GROUP_DELIMITER"}"
      if [[ -n "$group_entry" && -n "$host_entry" && "$group_entry" =~ ^[a-z0-9]+$ ]]; then
        # first time a group is seen initialize its entry, when same group seen again append host
        if [[ -z "${group_hosts_map[$group_entry]}" ]]; then
          group_hosts_map[$group_entry]="$h"
        else
          group_hosts_map[$group_entry]+=$'\n'$h
        fi
        continue
      fi
    fi
    main_hosts+=("$h")
  done

  # sort main hosts and group names alphabetically
  if [ "${#main_hosts[@]}" -gt 0 ]; then
    mapfile -t main_hosts < <(printf '%s\n' "${main_hosts[@]}" | sort -f)
  fi
  if [ "${#group_hosts_map[@]}" -gt 0 ]; then
    mapfile -t group_names < <(printf '%s\n' "${!group_hosts_map[@]}" | sort)
  fi

  #
  #         *** MAIN MENU SECTION ***
  #

  # prepare main menu labels, types, and values
  local labels=()
  local types=()
  local values=()
  for h in "${main_hosts[@]}"; do
    labels+=("${h^^}")
    types+=("host")
    values+=("$h")
  done
  for group_key in "${group_names[@]}"; do
    labels+=("${group_key^^}")
    types+=("group")
    values+=("$group_key")
  done

  # set main menu title and subtitle
  local main_title="VMS ${transport_label^^}"
  local main_subtitle="Select a ${CLR_GREEN}host${CLR_RESET} to connect to "
  main_subtitle+="or a ${CLR_ORANGE}group${CLR_RESET} to open its menu:"

  # main menu loop
  while true; do
    local current_msg="$last_msg"
    last_msg=""
    _render_menu "$main_title" "$main_subtitle" labels "$current_msg" 'types'

    # get host or group selection
    printf '\n'
    local selection
    local main_prompt="Enter number (or ${CLR_RED}E${CLR_RESET} to exit): "
    selection=$(_prompt_selection "$main_prompt" "${#labels[@]}" 0)
    case "$selection" in
      EXIT)
        clear
        return 0
        ;;
      INVALID)
        _clear_prev_input
        last_msg="Invalid selection, enter a number between 1 and ${#labels[@]} or E to exit."
        continue
        ;;
    esac

    # connect if host, or enter group menu if group
    local sel_index=$((selection-1))
    local sel_type="${types[sel_index]}"
    local sel_value="${values[sel_index]}"
    if [ "$sel_type" = "host" ]; then
      if _attempt_connection "$sel_value" "$transport_key" "$connect_fn" "$config_file" last_msg; then
        return 0
      fi
      continue
    fi

    #
    #         *** GROUP MENU SECTION ***
    #

    # get hosts in selected group
    local -a group_entries=()
    if [[ -n "${group_hosts_map[$sel_value]}" ]]; then
      mapfile -t group_entries < <(printf '%s\n' "${group_hosts_map[$sel_value]}" | sort -f)
    fi
    local group_count=${#group_entries[@]}
    if [ "$group_count" -eq 0 ]; then
      last_msg="No hosts in group ${sel_value^^}"
      continue
    fi

    # prepare host labels and values for group menu
    local group_labels=()
    local group_values=()
    for host_item in "${group_entries[@]}"; do
      local display="$host_item"
      if [[ "$host_item" == *"$GROUP_DELIMITER"* ]]; then
        display="${host_item#*"$GROUP_DELIMITER"}"
      fi
      group_labels+=("${display^^}")
      group_values+=("$host_item")
    done

    # set group menu title and subtitle
    local group_title="GROUP"
    local group_subtitle="${CLR_ORANGE}${sel_value^^} CLUSTER${CLR_RESET} - "
    group_subtitle+="select ${CLR_GREEN}host${CLR_RESET}:"

    # group menu loop
    while true; do
      local group_msg="$last_msg"
      last_msg=""
      _render_menu "$group_title" "$group_subtitle" group_labels "$group_msg"

      # get host selection in selected group
      printf '\n'
      local selection2
      local group_prompt="Enter number (${CLR_MAGENTA}B${CLR_RESET} to go back "
      group_prompt+="or ${CLR_RED}E${CLR_RESET} to exit): "
      selection2=$(_prompt_selection "$group_prompt" "$group_count" 1)
      case "$selection2" in
        EXIT)
          clear
          return 0
          ;;
        BACK)
          break
          ;;
        INVALID)
          _clear_prev_input
          last_msg="Invalid selection, enter a number between 1 and ${group_count}, B to go back, or E to exit."
          continue
          ;;
      esac

      # connect to selected host in group
      local host_index=$((selection2-1))
      local chosen_host="${group_values[host_index]}"
      if _attempt_connection "$chosen_host" "$transport_key" "$connect_fn" "$config_file" last_msg; then
        return 0
      fi
      continue
    done
  done
}
fi
