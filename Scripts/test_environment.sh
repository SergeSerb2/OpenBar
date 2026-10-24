#!/usr/bin/env bash

# Enumerate exported names only: never serialize inherited credential values.
openbar_scrub_test_environment() {
  local name
  while IFS= read -r name; do
    # Explicit non-secret controls and build search paths (_PAT also matches _PATH).
    # Do not allow OPENBAR_* wholesale; provider credentials use that prefix too.
    case "$name" in
      OPENBAR_ALLOW_TEST_KEYCHAIN_ACCESS|OPENBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS|\
      OPENBAR_DISABLE_KEYCHAIN_ACCESS|OPENBAR_USE_LOCAL_SWEETCOOKIEKIT|\
      LD_LIBRARY_PATH|DYLD_LIBRARY_PATH|DYLD_FRAMEWORK_PATH|LIBRARY_PATH|PKG_CONFIG_PATH) continue ;;
    esac
    if [[ "$name" =~ [Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Ww][Ee][Bb][Hh][Oo][Oo][Kk]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll]|[Cc][Oo][Oo][Kk][Ii][Ee]|[Pp][Rr][Ii][Vv][Aa][Tt][Ee]|_[Pp][Aa][Tt] ]]; then
      unset "$name"
    fi
  done < <(compgen -e)
}
openbar_scrub_test_environment
unset -f openbar_scrub_test_environment

# Inherited by test runners and their CLI children.
export OPENBAR_TEST_CODEX_FILE_ISOLATION=1
unset OPENBAR_TEST_CODEX_FILE_FIXTURES
export OPENBAR_TEST_SESSION_FILE_ISOLATION=1

if [[ "${OPENBAR_ALLOW_TEST_KEYCHAIN_ACCESS:-}" != "1" ]]; then
  export OPENBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1
fi
