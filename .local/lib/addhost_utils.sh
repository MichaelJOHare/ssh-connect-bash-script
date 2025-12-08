#!/bin/bash
# utility functions for addhost


_host_entry_exists() {
  local alias="$1"
  local config_file="$2"
  grep -Eq "^Host[[:space:]]+$alias$" "$config_file"
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

# returns array of aliases matching the given nickname
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

# normalize identifiers used for nicknames or groups
_normalize_identifier() {
  local raw="$1"
  local case_mode="${2:-lower}"
  local allow_empty="${3:-0}"
  local trimmed="${raw//[[:space:]]/}"

  if [[ -z "$trimmed" ]]; then
    if [[ "$allow_empty" -eq 1 ]]; then
      printf ''
      return 0
    fi
    return 1
  fi

  if [[ ! "$trimmed" =~ ^[A-Za-z0-9]+$ ]]; then
    return 2
  fi

  case "$case_mode" in
    upper) printf '%s' "${trimmed^^}" ;;
    lower) printf '%s' "${trimmed,,}" ;;
    *) printf '%s' "$trimmed" ;;
  esac
  return 0
}

# formats current algorithm settings for ssh host entry
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