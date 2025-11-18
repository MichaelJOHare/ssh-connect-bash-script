#!/bin/bash
if ! declare -F vmsmenu >/dev/null; then
vmsmenu() {
  # find ssh config file
  local ssh_config="$HOME/.ssh/config"
  [[ ! -r "$ssh_config" ]] && { printf 'SSH config not found: %s\n' "$ssh_config" >&2; return 1; }

  # read hosts from config file
  mapfile -t hosts < <(grep -E '^Host\s+' "$ssh_config" | awk '{print $2}')

  # early exit if no hosts found
  if [ ${#hosts[@]} -eq 0 ]; then
    printf 'No hosts found in %s\n' "$ssh_config" >&2
    return 1
  fi

  # split hosts into main list/favorites and clusters (xvms, l2, lp)
  local main_hosts=()
  local cluster_xvms=()
  local cluster_l2=()
  local cluster_lp=()

  for h in "${hosts[@]}"; do
    if [[ "$h" =~ ^xvms([._-]?.*) ]]; then
      cluster_xvms+=("$h")
    elif [[ "$h" =~ ^l2([._-]?.*) ]]; then
      cluster_l2+=("$h")
    elif [[ "$h" =~ ^lp([._-]?.*) ]]; then
      cluster_lp+=("$h")
    else
      main_hosts+=("$h")
    fi
  done

  # store last error message
  local last_msg=""

  # main menu loop
  while true; do
    clear
    printf '\n%s\n\n\r' "-----------------VMS MENU--------------------"
    printf '%s\n\n\r' "Select a host to connect to (type E to exit):"

    local labels=()
    local types=()
    local values=()

    # add main/favorite hosts
    for h in "${main_hosts[@]}"; do
      labels+=("$h")
      types+=("host")
      values+=("$h")
    done

    # add cluster entries if present
    if [ ${#cluster_xvms[@]} -gt 0 ]; then
      labels+=("XVMS Cluster")
      types+=("cluster")
      values+=("xvms")
    fi
    if [ ${#cluster_l2[@]} -gt 0 ]; then
      labels+=("L2 Cluster")
      types+=("cluster")
      values+=("l2")
    fi
    if [ ${#cluster_lp[@]} -gt 0 ]; then
      labels+=("LP Cluster")
      types+=("cluster")
      values+=("lp")
    fi

    # print main menu
    for idx in "${!labels[@]}"; do
      printf "%d) \033[0;32m%s\033[0m\n\r" $((idx+1)) "${labels[idx]}"
    done

	  # show last error message if there is one
    if [ -n "$last_msg" ]; then
      printf '\n\033[0;31m%s\033[0m\n\r' "$last_msg"
      last_msg=""
    fi

    local selection
    printf '\n'
    read -r -p "Enter number or E: " selection
    if [[ "$selection" =~ ^[Ee]$ ]]; then
      clear
      # set stty onlcr to default (is unset in bashrc)
      stty onlcr
      return 0
    elif [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#labels[@]}" ]; then
      :
    else
      _clear_prev_input
      last_msg="Invalid selection, enter a number between 1 and ${#labels[@]} or E to exit."
      continue
    fi

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

    # cluster submenu
    declare -n cluster_ref="cluster_${sel_value}"
    local cluster_count=${#cluster_ref[@]}
    if [ "$cluster_count" -eq 0 ]; then
      last_msg="No hosts in cluster ${sel_value^^}"
      continue
    fi

    while true; do
      clear
      printf '\n%s\n\n\r' "-----------------CLUSTER MENU--------------------"
      printf '%s\033[38;5;208m%s\033[0m%s\n\n\r' "" "${sel_value^^} Cluster" " - select host (B to go back, E to exit):"
      for j in $(seq 0 $((cluster_count-1))); do
        host_item=${cluster_ref[j]}
        # strip prefix and a separator (.-_) if it exists
        display="$host_item"
        if [[ "$host_item" =~ ^${sel_value}[._-]?(.*)$ ]]; then
          rest="${BASH_REMATCH[1]}"
          if [ -n "$rest" ]; then
            display="$rest"
          else
            display="$host_item"
          fi
        fi
        printf "%d) \033[0;32m%s\033[0m\n\r" $((j+1)) "$display"
      done

      # show last error message if there is one
      if [ -n "$last_msg" ]; then
        printf '\n\033[0;31m%s\033[0m\n\r' "$last_msg"
        last_msg=""
      fi

      local selection2
      printf '\n'
      read -r -p "Enter a number, B or E: " selection2
      if [[ "$selection2" =~ ^[Ee]$ ]]; then
        clear
        # set stty onlcr to default (is unset in bashrc)
        stty onlcr
        return 0
      elif [[ "$selection2" =~ ^[Bb]$ ]]; then
        break
      elif [[ "$selection2" =~ ^[0-9]+$ ]] && [ "$selection2" -ge 1 ] && [ "$selection2" -le "$cluster_count" ]; then
        local host_index=$((selection2-1))
        chosen_host=${cluster_ref[host_index]}
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
	      last_msg="Invalid selection, enter a number between 1 and ${cluster_count}, B to go back, or E to exit."
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
  if ! ssh "${user}@${host}"; then
    sleep 5
    return 1
  fi
  return 0
}

# clear line with ANSI escape sequence
_clear_prev_input() {
  printf '\033[1A\033[2K'
}
fi

# function to add host to ssh config
if ! declare -F addhost >/dev/null; then
addhost() {
  # set stty onlcr to default (is unset in bashrc)
  stty onlcr
  local ssh_config="$HOME/.ssh/config"
  local host
  local hostname
  local port
  while true; do
      clear
      printf '\n%s\n\n' "-----------------ADD HOST MENU--------------------\n"
      read -r -p "Enter nickname for the host (or E to exit): " host
      if [[ "$host" =~ ^[Ee]$ ]]; then
        clear
        return 0
      fi

      read -r -p"Enter hostname or IP address to add (or E to exit): " hostname
      if [[ "$hostname" =~ ^[Ee]$ ]]; then
        clear
        return 0
      fi

      read -r -p"Enter port (default 22): " port
      if [[ -z "$port" ]]; then
        port=22
      fi
      
      if [[ -n "$host" && -n "$hostname" && -n "$port" ]]; then
        break
      fi
  done

  {
    printf '\nHost %s\n' "$host"
    printf '    HostName %s\n' "$hostname"
    printf '    Port %s\n' "$port"
  } >> "$ssh_config"
  printf 'Added host \033[0;32m%s\033[0m (%s:%s) to %s\n' "$host" "$hostname" "$port" "$ssh_config"
}
fi