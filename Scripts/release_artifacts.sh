#!/usr/bin/env bash

openbar_release_arch_label() {
  local raw="${1:-arm64 x86_64}"
  local normalized
  local has_arm64=0
  local has_x86_64=0
  local arch

  normalized=$(printf "%s" "$raw" | tr ',' ' ')
  for arch in $normalized; do
    case "$arch" in
      arm64) has_arm64=1 ;;
      x86_64) has_x86_64=1 ;;
    esac
  done

  if [[ "$has_arm64" == "1" && "$has_x86_64" == "1" ]]; then
    printf "macos-universal"
    return
  fi
  if [[ "$has_arm64" == "1" ]]; then
    printf "macos-arm64"
    return
  fi
  if [[ "$has_x86_64" == "1" ]]; then
    printf "macos-x86_64"
    return
  fi

  printf "macos-%s" "$(printf "%s" "$normalized" | tr ' ' '+')"
}

openbar_app_zip_name() {
  local version=$1
  local arches="${2:-arm64 x86_64}"
  printf "OpenBar-%s-%s.zip" "$(openbar_release_arch_label "$arches")" "$version"
}

openbar_dsym_zip_name() {
  local version=$1
  local arches="${2:-arm64 x86_64}"
  printf "OpenBar-%s-%s.dSYM.zip" "$(openbar_release_arch_label "$arches")" "$version"
}
