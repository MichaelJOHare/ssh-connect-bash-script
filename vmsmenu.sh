#!/bin/bash
# interactive SSH/telnet launcher based on ~/.ssh/config and ~/.telnet/config entries

# TODO: allow switching transport mode (ssh/telnet) from within the menu
#       separate out the function of main (favorited) hosts and grouped hosts
#         - add ability to favorite hosts (e.g., via a separate favorites file?)
# low prio - clean up use of single vs double quotes in printf statements

#
#           ***HELPER FUNCTIONS***
#
_render_menu() {
  local title="$1"
  local subtitle="$2"
  local -n labels_ref="$3"
  local message="$4"
  local types_name="$5"
  local use_types=0
  local format_title="------------------------$title MENU------------------------"

  # check if types array is provided
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

_select_transport() {
  local -n _transport_out="$1"
  local selection
  while true; do
    clear
    printf '\n%s\n\n' "------------TRANSPORT MODE------------"
    printf '1) %s (default)\n' "${CLR_GREEN}SSH${CLR_RESET}"
    printf '2) %s\n\n' "${CLR_YELLOW}Telnet${CLR_RESET}"
    printf '%s' "Enter number (or ${CLR_RED}E${CLR_RESET} to exit) [${CLR_GREEN}1${CLR_RESET}]: "
    read -r selection
    case "$selection" in
      ''|1)
        _transport_out='ssh'
        return 0
        ;;
      2)
        _transport_out='telnet'
        return 0
        ;;
      [Ee])
        return 1
        ;;
      *)
        _clear_prev_input
        printf '%s\n' "${CLR_RED}Invalid selection.${CLR_RESET}"
        sleep 1
        ;;
    esac
  done
}

#
#           *** MENU FUNCTION ***
#
if ! declare -F vmsmenu >/dev/null; then
vmsmenu() {
  # store error messages
  local last_msg=""

  # choose transport, ssh (default) or telnet
  local transport_key=""
  if ! _select_transport transport_key; then
    clear
    return 0
  fi

  # prepare config file and connect function based on transport choice
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
      last_msg=""
      local connect_result
      "$connect_fn" "$sel_value" "$config_file"
      connect_result=$?
      if [ $connect_result -eq 0 ]; then
        return 0
      elif [ "$transport_key" = "ssh" ] && [ $connect_result -eq 2 ]; then
        last_msg="Error: username required"
      else
        last_msg="Connection to $sel_value failed — returned to main menu"
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
      last_msg=""
      local connect_result
      "$connect_fn" "$chosen_host" "$config_file"
      connect_result=$?
      if [ $connect_result -eq 0 ]; then
        return 0
      elif [ "$transport_key" = "ssh" ] && [ $connect_result -eq 2 ]; then
        last_msg="Error: username required"
      else
        last_msg="Connection to $chosen_host failed — returning to cluster menu"
      fi
      continue
    done
  done
}

_ssh_connect() {
  local host="$1"
  local user
  printf '%s as: ' "${CLR_MAGENTA}login${CLR_RESET}"
  read -r user
  if [[ -z "$user" ]]; then
    return 2
  fi
  clear
  printf 'Connecting to %s as %s...\n' "${CLR_GREEN}$host${CLR_RESET}" "${CLR_MAGENTA}$user${CLR_RESET}"
  printf '\033]0;%s\007' "$user@$host"
  if ! ssh "${user}@${host}"; then       # set ConnectTimeout, add visual for long waits?
    printf '\033]0;%s\007' "VMS MENU"    # if ssh fails, prompt to try telnet?
    printf 'SSH connection to %s failed. Returning to menu in 5 seconds...\n' "${CLR_GREEN}$host${CLR_RESET}"
    sleep 5
    return 1
  fi
  printf '\033]0;%s\007' "VMS MENU"
  return 0
}

_telnet_connect() {
  local host="$1"
  local config_file="$2"
  local entry hostname port

  # get hostname/port since telnet needs them directly
  entry="$(_read_host_values "$host" "$config_file")"
  IFS='|' read -r hostname port _ <<< "$entry"
  printf '%s' "host: $host, entry: $entry, hostname: $hostname, port: $port"  # DEBUG

  if [[ -z "$hostname" ]]; then
    printf '%s\n' "${CLR_RED}No telnet hostname/IP configured for ${host}${CLR_RESET}"
    sleep 5
    return 1
  fi

  clear
  printf 'Connecting to %s via telnet...\n' "${CLR_GREEN}$hostname${CLR_RESET}"
  printf '\033]0;%s\007' "telnet:$host"
  if ! telnet "$hostname" "${port:-23}"; then
    printf '\033]0;%s\007' "VMS MENU"
    printf 'Telnet connection to %s failed. Returning to menu in 5 seconds...\n' "${CLR_GREEN}$host${CLR_RESET}"
    sleep 5
    return 1
  fi
  printf '\033]0;%s\007' "VMS MENU"
  return 0
}
fi
