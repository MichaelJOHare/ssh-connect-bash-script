#!/bin/bash
# utility functions for vmsmenu/addhost

#
#             ***SHARED UTILITIES AND CONSTANTS***
#

# define group delimiter constant globally (group.HOST)
: "${GROUP_DELIMITER:=.}"
readonly GROUP_DELIMITER

# ANSI escape color constants
# shellcheck disable=SC2034
{
readonly CLR_GREEN=$'\033[0;32m'
readonly CLR_RED=$'\033[0;31m'
readonly CLR_MAGENTA=$'\033[0;35m'
readonly CLR_ORANGE=$'\033[38;5;208m'
readonly CLR_YELLOW=$'\033[0;33m'
readonly CLR_RESET=$'\033[0m'
}

_clear_prev_input() {
  printf '\033[1A\033[2K'
}

_ensure_config_file() {
  local config_path="$1"
  local config_dir
  config_dir="$(dirname "$config_path")"
  mkdir -p "$config_dir" || return 1
  touch "$config_path" || return 1
}

_host_entry_exists() {
  local alias="$1"
  local config_file="$2"
  grep -Eq "^Host[[:space:]]+$alias$" "$config_file"
}

_read_host_values() {
  local alias="$1"
  local config_file="$2"
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
  done < "$config_file"
  printf '%s|%s|%s|%s|%s\n' "${hostname:-}" "${port:-}" "${hostkey:-}" "${kex:-}" "${macs:-}"
}

_remove_host_entry() {
  local alias="$1"
  local config_file="$2"
  local tmp_file
  tmp_file="$(mktemp)" || return 1
  awk -v target="$alias" '
    BEGIN { skip=0 }
    /^Host[ \t]+/ {
      if (skip) { skip=0 }
      match($0, /^Host[ \t]+(.+)$/, m)
      if (m[1] == target) { skip=1; next }
    }
    skip { next }
    { print }
  ' "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
}

_append_host_entry() {
  local alias="$1"
  local hostname="$2"
  local port="$3"
  local config_file="$4"
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
  } >> "$config_file"
}

_load_host_aliases() {
  local config_file="$1"
  awk '/^Host[[:space:]]+/ { for (i=2; i<=NF; i++) print $i }' "$config_file"
}

_list_config_groups() {
  local config_file="$1"
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
      for (g in groups) { print g }
    }
  ' "$config_file" 2>/dev/null | sort
}

_find_aliases_for_nickname() {
  local nickname="$1"
  local config_file="$2"
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
  ' "$config_file"
}

#
#          ***VMSMENU HELPERS***
#

_render_menu() {
  local title="$1"
  local subtitle="$2"
  local -n labels_ref="$3"
  local message="$4"
  local types_name="$5"
  local use_types=0
  local format_title="------------------------$title MENU------------------------"

  # check if types array is provided for main vmsmenu
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
  local title="$2"
  local selection
  while true; do
    clear
    printf '\n%s\n\n' "------------${title^^}------------"
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

  if [[ -z "$hostname" ]]; then
    return 3
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


#
#          ***ADDHOST HELPERS***
#

_format_algo_display() {
  local value="$1"
  local label="$2"
  local display="${value:-<default>}"
  if [[ "$display" == "<default>" ]]; then
    printf '  %s: %s\n' "$label" "${CLR_ORANGE}$display${CLR_RESET}"
  else
    printf '  %s: %s\n' "$label" "${CLR_MAGENTA}$display${CLR_RESET}"
  fi
}