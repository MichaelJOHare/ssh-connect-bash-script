#!/bin/bash
# interactive SSH launcher based on ~/.ssh/config entries

# TODO: add telnet support using ~/.telnet/config
#       maybe first menu option should ask user to choose between ssh and telnet? (default ssh)
#       separate out the function of main (favorited) hosts and grouped hosts
#         - add ability to favorite hosts (e.g., via a separate favorites file?)
# low prio - clean up use of single vs double quotes in printf statements

# load ssh config helpers
source "$HOME/.local/lib/ssh_config_utils.sh"

# ANSI escape color constants
readonly CLR_GREEN=$'\033[0;32m'
readonly CLR_RED=$'\033[0;31m'
readonly CLR_MAGENTA=$'\033[0;35m'
readonly CLR_ORANGE=$'\033[38;5;208m'
readonly CLR_RESET=$'\033[0m'

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
  printf '\n%s\n\n\r' "$format_title"
  if [[ -n "$subtitle" ]]; then
    printf '%s\n\n\r' "$subtitle"
  fi

  # if type is group, color orange; if host, color green
  for idx in "${!labels_ref[@]}"; do
    local entry_type=""
    if (( use_types )); then
      entry_type="${types_ref[idx]}"
    fi
    if [[ "$entry_type" == "group" ]]; then
      printf "%d) %s%s CLUSTER%s\n\r" $((idx+1)) "$CLR_ORANGE" "${labels_ref[idx]}" "$CLR_RESET"
    else
      printf "%d) %s%s%s\n\r" $((idx+1)) "$CLR_GREEN" "${labels_ref[idx]}" "$CLR_RESET"
    fi
  done

  # display message if any
  if [[ -n "$message" ]]; then
    printf '\n%s%s%s\n\r' "$CLR_RED" "$message" "$CLR_RESET"
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

#
#           *** MENU FUNCTION ***
#
if ! declare -F vmsmenu >/dev/null; then
vmsmenu() {
  # store error messages
  local last_msg=""

  # find ssh config
  local ssh_config="$HOME/.ssh/config"
  _ensure_ssh_config "$ssh_config" || {
    printf 'Unable to access %s\n' "$ssh_config" >&2
    return 1
  }

  # find telnet config
  local telnet_config="$HOME/.telnet/config"
  _ensure_telnet_config "$telnet_config" || { 
    printf 'Telnet config not found: %s\n' "$telnet_config" >&2; 
    return 1; 
  }

  # gather all ssh hosts
  mapfile -t hosts < <(awk '/^Host[[:space:]]+/ { for (i=2; i<=NF; i++) print $i }' "$ssh_config")
  if [ ${#hosts[@]} -eq 0 ]; then
    printf 'No hosts found in %s\n' "$ssh_config" >&2
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
        if [[ -z "${group_hosts_map[$group_entry]}" ]]; then
          group_hosts_map[$group_entry]="$h"
        else
          group_hosts_map[$group_entry]+=$'\n'"$h"
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
  local main_title="VMS"
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
        #stty onlcr
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
      local ssh_result
      _ssh_connect "$sel_value"
      ssh_result=$?
      if [ $ssh_result -eq 0 ]; then
        return 0
      elif [ $ssh_result -eq 2 ]; then
        last_msg="Error: username required"
        continue
      else
        last_msg="SSH failed to connect to ${sel_value} — returned to main menu"
        continue
      fi
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

    # prepare group host labels and values
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
          #stty onlcr
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
      local ssh_result
      _ssh_connect "$chosen_host"
      ssh_result=$?
      if [ $ssh_result -eq 0 ]; then
        return 0
      elif [ $ssh_result -eq 2 ]; then
        last_msg="Error: username required"
        continue
      else
        last_msg="SSH failed to connect to ${chosen_host} — returning to cluster menu"
        continue
      fi
    done
  done
}

_ssh_connect() {
  local host="$1"
  local user
  printf '\r%slogin%s' "$CLR_MAGENTA" "$CLR_RESET"
  read -r -p " as: " user
  if [[ -z "$user" ]]; then
    return 2
  fi
  clear
  printf 'Connecting to %s%s%s as %s%s%s...\n\r' "$CLR_GREEN" "$host" "$CLR_RESET" "$CLR_MAGENTA" "$user" "$CLR_RESET"
  # set stty onlcr so it is back to default after logging out of ssh (it is unset in bashrc)
  # interestingly, this does not apply to the ssh session itself
  #stty onlcr     ...wtf this doesn't seem to do anything anymore?
  printf '\033]0;%s@%s\007' "$user" "$host"
  if ! ssh "${user}@${host}"; then       # set ConnectTimeout, add visual for long waits?
    printf '\033]0;%s\007' "VMS MENU"
    sleep 5
    return 1
  fi
  printf '\033]0;%s\007' "VMS MENU"
  return 0
}
fi
