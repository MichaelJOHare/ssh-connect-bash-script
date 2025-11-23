#!/bin/bash
# shared SSH config helpers for vmsmenu/addhost

GROUP_DELIMITER='.'
_clear_prev_input() {
  printf '\033[1A\033[2K'
}

_ensure_ssh_config() {
  # ensure ssh config file exists, create one if not
  local ssh_config="$1"
  local ssh_dir
  ssh_dir="$(dirname "$ssh_config")"
  mkdir -p "$ssh_dir" || return 1
  touch "$ssh_config" || return 1
}

_host_entry_exists() {
  local alias="$1"
  local ssh_config="$2"
  grep -Eq "^Host[[:space:]]+$alias$" "$ssh_config"
}

_read_host_values() {
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
      for (g in groups) { print g }
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
