#!/bin/bash

# TEST NEED FOR CONVULUTED PROFILE LAUNCH IN WINDOWS TERMINAL AFTER ~/.BASH_PROFILE CHANGE
GROUP_DELIMITER='.'
if ! declare -F vmsmenu >/dev/null; then
vmsmenu() {
  # find ssh config file
  local ssh_config="$HOME/.ssh/config"
  [[ ! -r "$ssh_config" ]] && { printf 'SSH config not found: %s\n' "$ssh_config" >&2; return 1; }

  # read hosts from config file
  mapfile -t hosts < <(awk '/^Host[[:space:]]+/ { for (i=2; i<=NF; i++) print $i }' "$ssh_config")

  # early exit if no hosts found
  if [ ${#hosts[@]} -eq 0 ]; then
    printf 'No hosts found in %s\n' "$ssh_config" >&2
    return 1
  fi

  # organize hosts into "favorited" hosts and named groups (group.HOST)
  local main_hosts=()
  local -A group_hosts_map=()
  local -a group_names=()

  # split hosts into main and groups so hosts in a group can be collapsed into their group name in main menu
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

  # sort main hosts and group names
  if [ "${#main_hosts[@]}" -gt 0 ]; then
    mapfile -t main_hosts < <(printf '%s\n' "${main_hosts[@]}" | sort -f)
  fi
  if [ "${#group_hosts_map[@]}" -gt 0 ]; then
    mapfile -t group_names < <(printf '%s\n' "${!group_hosts_map[@]}" | sort)
  fi

  # store last error message
  local last_msg=""

  # main menu loop
  while true; do
    clear
    printf '\n%s\n\n\r' "-----------------VMS MENU--------------------"
    printf '%s\n\n\r' "Select a host to connect to:"

    local labels=()
    local types=()
    local values=()

    # add main/favorite hosts
    for h in "${main_hosts[@]}"; do
      labels+=("${h^^}")
      types+=("host")
      values+=("$h")
    done

    # add group entries if present
    for group_key in "${group_names[@]}"; do
      labels+=("${group_key^^}")
      types+=("group")
      values+=("$group_key")
    done

    # print main menu
    for idx in "${!labels[@]}"; do
      printf "%d) \033[0;32m%s\033[0m\n\r" $((idx+1)) "${labels[idx]}"
    done

	  # show last error message if there is one
    if [ -n "$last_msg" ]; then
      printf '\n\033[0;31m%s\033[0m\n\r' "$last_msg"
      last_msg=""
    fi

    # get main menu selection
    local selection
    printf '\n'
    read -r -p "Enter number (or E to exit): " selection
    if [[ "$selection" =~ ^[Ee]$ ]]; then
      clear
      # set stty onlcr to default on early exit (is unset in bashrc)
      stty onlcr
      return 0
    elif [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#labels[@]}" ]; then
      :
    else
      _clear_prev_input
      last_msg="Invalid selection, enter a number between 1 and ${#labels[@]} or E to exit."
      continue
    fi

    # if host selected, connect via ssh otherwise show group submenu
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

    # grab host entries for selected group
    local -a group_entries=()
    if [[ -n "${group_hosts_map[$sel_value]}" ]]; then
      mapfile -t group_entries < <(printf '%s\n' "${group_hosts_map[$sel_value]}" | sort -f)
    fi
    local group_count=${#group_entries[@]}
    if [ "$group_count" -eq 0 ]; then
      last_msg="No hosts in group ${sel_value^^}"
      continue
    fi

    # group submenu loop
    while true; do
      clear
      printf '\n%s\n\n\r' "-----------------GROUP MENU--------------------"
      printf '\033[38;5;208m%s\033[0m%s\n\n\r' "${sel_value^^} CLUSTER" " - select host:"

      # print group entries
      for j in $(seq 0 $((group_count-1))); do
        host_item=${group_entries[j]}
        display="$host_item"
        if [[ "$host_item" == *"$GROUP_DELIMITER"* ]]; then
          display="${host_item#*"$GROUP_DELIMITER"}"
        fi
        display="${display^^}"
        printf "%d) \033[0;32m%s\033[0m\n\r" $((j+1)) "$display"
      done

      # show last error message if there is one
      if [ -n "$last_msg" ]; then
        printf '\n\033[0;31m%s\033[0m\n\r' "$last_msg"
        last_msg=""
      fi

      # get group menu selection
      local selection2
      printf '\n'
      read -r -p "Enter a number (B to go back, E to exit): " selection2
      if [[ "$selection2" =~ ^[Ee]$ ]]; then
        clear
        stty onlcr   # set stty onlcr to default on early exit (is unset in bashrc)
        return 0
      elif [[ "$selection2" =~ ^[Bb]$ ]]; then
        break

      # connect to selected host in group menu  
      elif [[ "$selection2" =~ ^[0-9]+$ ]] && [ "$selection2" -ge 1 ] && [ "$selection2" -le "$group_count" ]; then
        local host_index=$((selection2-1))
        chosen_host=${group_entries[host_index]}
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
      else
        _clear_prev_input
        last_msg="Invalid selection, enter a number between 1 and ${group_count}, B to go back, or E to exit."
      fi
    done
  done
}

_ssh_connect() {
  local host="$1"
  local user
  printf "\r\033[0;35mlogin\033[0m"
  read -r -p " as: " user
  if [[ -z "$user" ]]; then
    return 2
  fi
  clear
  printf 'Connecting to \033[0;32m%s\033[0m as \033[0;35m%s\033[0m...\n\r' "$host" "$user"
  # set stty onlcr so it is back to default after logging out of ssh (it is unset in bashrc)
  # interestingly, this does not apply to the ssh session itself
  stty onlcr
  printf '\033]0;%s@%s\007' "$user" "$host"
  if ! ssh "${user}@${host}"; then     # set ConnectTimeout, add visual for long waits?
    printf '\033]0;%s\007' "VMS MENU"  # make these PWD instead?
    sleep 5
    return 1
  fi
  printf '\033]0;%s\007' "VMS MENU"
  return 0
}

_clear_prev_input() {
  printf '\033[1A\033[2K'
}
fi

# only needed if we keep it so that windows terminal auto launches vmsmenu
#   since vmsmenu exits early when ssh config is missing, maybe implement this into vmsmenu
_ensure_ssh_config() {
  # ensure ssh config file exists, create one if not
  local ssh_config="$1"
  local ssh_dir
  ssh_dir="$(dirname "$ssh_config")"
  mkdir -p "$ssh_dir" || return 1
  touch "$ssh_config" || return 1
}

_host_entry_exists() {
  # check if host entry exists in ssh config
  local alias="$1"
  local ssh_config="$2"
  grep -Eq "^Host[[:space:]]+$alias$" "$ssh_config"
}

# maybe implement some of these helpers into vmsmenu?
_read_host_values() {
  # read host entry values from ssh config
  local alias="$1"
  local ssh_config="$2"
  local line current in_block hostname port hostkey kex macs
  while IFS= read -r line; do
    if [[ "$line" =~ ^Host[[:space:]]+(.+)$ ]]; then
      current="${BASH_REMATCH[1]}"
      if [[ "$current" == "$alias" ]]; then
        in_block=1
        continue
      elif [[ -n "$in_block" ]]; then
        break
      fi
    elif [[ -n "$in_block" ]]; then
      if [[ "$line" =~ ^[[:space:]]*([A-Za-z][A-Za-z0-9]*)([[:space:]]+)(.+)$ ]]; then
        # extract ssh config fields along with their values
        local key="${BASH_REMATCH[1],,}"
        local value="${BASH_REMATCH[3]}"
        case "$key" in
          hostname) hostname="$value" ;;
          port) port="$value" ;;
          hostkeyalgorithms) hostkey="$value" ;;
          kexalgorithms) kex="$value" ;;
          macs) macs="$value" ;;
        esac
      fi
    fi
  done < "$ssh_config"
  printf '%s|%s|%s|%s|%s\n' "${hostname:-}" "${port:-}" "${hostkey:-}" "${kex:-}" "${macs:-}"
}

_remove_host_entry() {
  local alias="$1"
  local ssh_config="$2"
  local tmp_file
  tmp_file="$(mktemp)" || return 1
  # make a temp copy of ssh config without the specified host entry and replace original with it
  awk -v target="$alias" '
    BEGIN { skip=0 }
    /^Host[ \t]+/ {
      if (skip) { skip=0 }
      match($0, /^Host[ \t]+(.+)$/, m)
      if (m[1] == target) { skip=1; next }
    }
    skip { next }
    { print }
  ' "$ssh_config" > "$tmp_file" && mv "$tmp_file" "$ssh_config"
}

_append_host_entry() {
  local alias="$1"
  local hostname="$2"
  local port="$3"
  local ssh_config="$4"
  local hostkey="$5"
  local kex="$6"
  local macs="$7"
  {
    printf '\nHost %s\n' "$alias"
    printf '    Hostname %s\n' "$hostname"
    printf '    Port %s\n' "$port"
    if [[ -n "$hostkey" ]]; then
      printf '    HostKeyAlgorithms %s\n' "$hostkey"
    fi
    if [[ -n "$kex" ]]; then
      printf '    KexAlgorithms %s\n' "$kex"
    fi
    if [[ -n "$macs" ]]; then
      printf '    MACs %s\n' "$macs"
    fi
  } >> "$ssh_config"
}

_list_config_groups() {
  local ssh_config="$1"
  awk -v d="$GROUP_DELIMITER" '
    /^Host[[:space:]]+/ {
      for (i=2; i<=NF; i++) {
        alias=$i
        pos=index(alias, d)
        if (pos > 0) {
          group=substr(alias, 1, pos-1)
          group_lower=tolower(group)
          if (group_lower ~ /^[a-z0-9]+$/) {
            groups[group_lower]=1
          }
        }
      }
    }
    END {
      for (g in groups) {
        print g
      }
    }
  ' "$ssh_config" 2>/dev/null | sort
}

_find_aliases_for_nickname() {
  local nickname="$1"
  local ssh_config="$2"
  local upper_nick="${nickname^^}"
  awk -v nick="$upper_nick" -v d="$GROUP_DELIMITER" '
    /^Host[[:space:]]+/ {
      for (i=2; i<=NF; i++) {
        alias=$i
        alias_upper=toupper(alias)
        if (alias_upper == nick) {
          print alias
          continue
        }
        pos=index(alias, d)
        if (pos > 0) {
          member=toupper(substr(alias, pos+length(d)))
          if (member == nick) {
            print alias
          }
        }
      }
    }
  ' "$ssh_config"
}

if ! declare -F addhost >/dev/null; then
#  add ability to list hosts/groups -> hosts and their port/algos/etc.
addhost() {
  stty onlcr     # set stty onlcr to default (is unset in bashrc)

  # ensure ssh config file exists, it is created if not
  local ssh_config="$HOME/.ssh/config"
  _ensure_ssh_config "$ssh_config" || { printf 'Unable to access %s\n' "$ssh_config" >&2; return 1; }

  # main menu loop
  while true; do
      clear
      printf '\n%s\n\n\n' "-----------------ADD HOST MENU--------------------"

      # list existing groups
      local -a existing_groups=()
      mapfile -t existing_groups < <(_list_config_groups "$ssh_config")
      if [ "${#existing_groups[@]}" -gt 0 ]; then
        printf 'Existing groups: \033[0;32m%s\033[0m\n\n' "$(IFS=', '; echo "${existing_groups[*]^^}")"
      fi

      # get nickname for host
      printf "Enter unique \033[0;32mnickname\033[0m"
      read -r -p " for the host (or E to exit): " host
      if [[ "$host" =~ ^[Ee]$ ]]; then
        clear
        return 0
      fi

      # sanitize nickname input
      host="${host//[[:space:]]/}"
      if [[ "$host" == *"$GROUP_DELIMITER"* ]]; then
        printf '\033[0;31mNicknames cannot include %s; use the group option instead.\033[0m\n' "$GROUP_DELIMITER"
        sleep 2
        continue
      fi
      if [[ -z "$host" ]]; then
        printf '\033[0;31mNickname is required.\033[0m\n' # change these to not use sleep like vmsmenu (persistent last_msg)
        sleep 2
        continue
      fi

      local nickname="${host^^}"
      local -a matching_aliases=()
      mapfile -t matching_aliases < <(_find_aliases_for_nickname "$nickname" "$ssh_config")
      local host_alias=""
      local group_name=""

      # ensure .ssh/config nicknames are unique
      if [ "${#matching_aliases[@]}" -gt 0 ]; then
        if [ "${#matching_aliases[@]}" -gt 1 ]; then
          printf '\nNickname \033[0;32m%s\033[0m exists in multiple host entries:\n' "$nickname"
          for idx in "${!matching_aliases[@]}"; do
            printf '  %d) %s\n' $((idx+1)) "${matching_aliases[idx]}"
          done

          # prompt user to select which entry to edit when multiple matches found
          local alias_choice=""
          while true; do
            read -r -p "Nicknames should be unique. Select entry to edit (1-${#matching_aliases[@]}) or E to cancel: " alias_choice
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
            sleep 1
            continue
          fi
        else
          host_alias="${matching_aliases[0]}"
        fi

        # catch nickname input from user that matches existing host
        printf '\nHost \033[0;32m%s\033[0m already exists.\n' "$host_alias"
        read -r -p "Edit this host? (Y/n): " edit_choice
        if [[ "$edit_choice" =~ ^[Nn]$ ]]; then
          continue
        fi
        if [[ "$host_alias" == *"$GROUP_DELIMITER"* ]]; then
          group_name="${host_alias%%"$GROUP_DELIMITER"*}"
        else
          group_name=""
        fi
      else
        local belongs_group="n"
        read -r -p "Is this host part of a group? (y/N): " belongs_group
        if [[ "$belongs_group" =~ ^[Yy]$ ]]; then
          read -r -p "Enter group name (letters/numbers): " group_name
          group_name="${group_name//[[:space:]]/}"
          group_name="${group_name,,}"
          if [[ -z "$group_name" || ! "$group_name" =~ ^[a-z0-9]+$ ]]; then
            printf 'Group names must be letters/numbers.\n'
            sleep 2
            continue
          fi
        fi
        host_alias="$nickname"
        if [[ -n "$group_name" ]]; then
          host_alias="${group_name}${GROUP_DELIMITER}${nickname}"
        fi
      fi

      local hostname=""
      local port="22"
      local hostkey=""
      local kex=""
      local macs=""

      if _host_entry_exists "$host_alias" "$ssh_config"; then
        IFS='|' read -r hostname port hostkey kex macs <<< "$( _read_host_values "$host_alias" "$ssh_config" )"
        [[ -z "$port" ]] && port="22"
      fi

      read -r -p "Enter hostname or IP${hostname:+ [$hostname]} (or E to cancel): " hostname_input
      if [[ "$hostname_input" =~ ^[Ee]$ ]]; then
        continue
      fi
      if [[ -n "$hostname_input" ]]; then
        hostname="$hostname_input"
      fi
      if [[ -z "$hostname" ]]; then
        printf 'Hostname/IP is required.\n'
        sleep 2
        continue
      fi

      read -r -p "Enter port [${port:-22}]: " port_input
      if [[ "$port_input" =~ ^[Ee]$ ]]; then
        continue
      fi
      if [[ -n "$port_input" ]]; then
        port="$port_input"
      fi
      if [[ -z "$port" ]]; then
        port="22"
      fi

      local -a algo_flags=()
      [[ -n "$hostkey" ]] && algo_flags+=("H")
      [[ -n "$kex" ]] && algo_flags+=("K")
      [[ -n "$macs" ]] && algo_flags+=("M")
      local algo_hint=""
      if [ "${#algo_flags[@]}" -gt 0 ]; then
        algo_hint=" (current: ${algo_flags[*]})" # change color? maybe show the entries for each flag?
      fi

      # configure algorithms for host
      local algo_choice=""
      read -r -p "Configure algorithms (H,K,M e.g. HK)${algo_hint}, Enter to skip: " algo_choice  # find better way to show current?
      algo_choice="${algo_choice^^}"
      algo_choice="${algo_choice//[^HKM]/}"
      if [[ -n "$algo_choice" ]]; then
        if [[ "$algo_choice" == *"H"* ]]; then
          local hostkey_input
          read -r -p "HostKeyAlgorithms${hostkey:+ [$hostkey]} (blank keeps current, '-' removes): " hostkey_input
          if [[ "$hostkey_input" == '-' ]]; then
            hostkey=""
          elif [[ -n "$hostkey_input" ]]; then
            hostkey="+$hostkey_input"
          fi
        fi
        if [[ "$algo_choice" == *"K"* ]]; then
          local kex_input
          read -r -p "KexAlgorithms${kex:+ [$kex]} (blank keeps current, '-' removes): " kex_input
          if [[ "$kex_input" == '-' ]]; then
            kex=""
          elif [[ -n "$kex_input" ]]; then
            kex="+$kex_input"
          fi
        fi
        if [[ "$algo_choice" == *"M"* ]]; then
          local macs_input
          read -r -p "MACs${macs:+ [$macs]} (blank keeps current, '-' removes): " macs_input
          if [[ "$macs_input" == '-' ]]; then
            macs=""
          elif [[ -n "$macs_input" ]]; then
            macs="+$macs_input"
          fi
        fi
      fi

      _remove_host_entry "$host_alias" "$ssh_config"
      _append_host_entry "$host_alias" "$hostname" "$port" "$ssh_config" "$hostkey" "$kex" "$macs"
      printf 'Saved host \033[0;32m%s\033[0m (%s:%s) to %s\n' "$host_alias" "$hostname" "$port" "$ssh_config"

      read -r -p "Add or edit another host? (y/N): " add_more
      if [[ ! "$add_more" =~ ^[Yy]$ ]]; then
        clear
        return 0
      fi
  done
}
fi