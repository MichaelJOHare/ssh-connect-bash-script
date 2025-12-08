#!/bin/bash
# utility functions shared by vmsmenu and addhost


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

# prompt to select transport type (ssh/telnet)
_select_transport() {
  local -n _transport_out="$1"
  local selection
  while true; do
    clear
    printf '\n%s\n\n' "------------SELECT CONNECTION METHOD------------"
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

# resolve the config file for a transport (ssh/telnet) and ensure it exists
_prepare_transport_config() {
  local transport="$1"
  local -n _label_ref="$2"
  local -n _config_ref="$3"

  case "$transport" in
    telnet)
      _label_ref="Telnet"
      _config_ref="$HOME/.telnet/config"
      ;;
    *)
      _label_ref="SSH"
      _config_ref="$HOME/.ssh/config"
      ;;
  esac

  _ensure_config_file "$_config_ref"
}

_ensure_config_file() {
  local config_path="$1"
  local config_dir
  config_dir="$(dirname "$config_path")"
  mkdir -p "$config_dir" || return 1
  touch "$config_path" || return 1
}

# split host aliases into main list and grouped map for menu rendering
_split_hosts_by_group() {
  local -n _source_hosts="$1"
  local -n _main_out="$2"
  local -n _group_map_out="$3"
  local -n _group_names_out="$4"
  local host group_key group_member

  _main_out=()
  for host in "${_source_hosts[@]}"; do
    if [[ "$host" == *"$GROUP_DELIMITER"* ]]; then
      local group_key="${host%%"$GROUP_DELIMITER"*}"
      local group_member="${host#*"$GROUP_DELIMITER"}"
      if [[ -n "$group_key" && -n "$group_member" && "$group_key" =~ ^[a-z0-9]+$ ]]; then
        if [[ -z "${_group_map_out["$group_key"]}" ]]; then
          _group_map_out["$group_key"]="$host"
        else
          _group_map_out["$group_key"]+=$'\n'$host
        fi
        continue
      fi
    fi
    _main_out+=("$host")
  done

  if [ "${#_main_out[@]}" -gt 0 ]; then
    mapfile -t _main_out < <(printf '%s\n' "${_main_out[@]}" | sort -f)
  fi

  if [ "${#_group_map_out[@]}" -gt 0 ]; then
    mapfile -t _group_names_out < <(printf '%s\n' "${!_group_map_out[@]}" | sort)
  else
    _group_names_out=()
  fi
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

_load_host_aliases() {
  local config_file="$1"
  awk '/^Host[[:space:]]+/ { for (i=2; i<=NF; i++) print $i }' "$config_file"
}

_format_host_display() {
  local host="$1"

  if [[ "$host" == *"$GROUP_DELIMITER"* ]]; then
    local group="${host%%"$GROUP_DELIMITER"*}"
    local member="${host#*"$GROUP_DELIMITER"}"
    printf '%s' "${CLR_ORANGE}${group^^} ${CLR_GREEN}${member^^}${CLR_RESET}"
  else
    printf '%s' "${CLR_GREEN}${host^^}${CLR_RESET}"
  fi
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