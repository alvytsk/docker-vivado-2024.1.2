#!/usr/bin/env bats

load helpers

setup() {
  source "$REPO_ROOT/lib/installer.sh"
  TMP="$(mktemp -d)"
  cat > "$TMP/xsetup" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARGV_LOG"
EOF
  chmod +x "$TMP/xsetup"
  export ARGV_LOG="$TMP/argv"
}

teardown() { rm -rf "$TMP"; }

# Each of these asserts the COMPLETE argv, in order, one argument per line.
# Substring matching is not enough: `-c` silently changed to `-l`, a dropped
# config flag, or a reordering that puts -b before -a would all still contain
# the word "Update". The whole point of this file is that the argv is exact,
# because it is only ever discovered to be wrong four hours into Task 10.
#
# These expectations and lib/installer.sh change TOGETHER. If Task 2 recorded
# an Update form that is not `-c <config>`, edit the heredoc below in the same
# commit as the function -- a diff that touches only one of them is the bug.
expect_argv() {
  printf '%s\n' "$@" > "$TMP/expected"
  diff -u "$TMP/expected" "$ARGV_LOG"
}

@test "xsetup_install passes exactly the recorded Install argv" {
  xsetup_install "$TMP/xsetup" /tmp/cfg.txt
  run expect_argv -a XilinxEULA,3rdPartyEULA -b Install -c /tmp/cfg.txt
  [ "$status" -eq 0 ]
}

@test "xsetup_update passes exactly the recorded Update argv" {
  xsetup_update "$TMP/xsetup" /tmp/cfg.txt
  run expect_argv -a XilinxEULA,3rdPartyEULA -b Update -c /tmp/cfg.txt
  [ "$status" -eq 0 ]
}

@test "xsetup_add passes exactly the recorded Add argv" {
  xsetup_add "$TMP/xsetup" /tmp/cfg.txt
  run expect_argv -a XilinxEULA,3rdPartyEULA -b Add -c /tmp/cfg.txt
  [ "$status" -eq 0 ]
}

@test "the EULA flag arrives as ONE argument, not two split words" {
  # Redundant with the argv tests only while XSETUP_EULA stays an array;
  # this is the test that names the failure if someone makes it a string.
  xsetup_install "$TMP/xsetup" /tmp/cfg.txt
  run grep -c '^XilinxEULA,3rdPartyEULA$' "$ARGV_LOG"
  [ "$output" = "1" ]
}

@test "a config path containing a space survives as one argument" {
  xsetup_install "$TMP/xsetup" "/tmp/two words.txt"
  run grep -c '^/tmp/two words\.txt$' "$ARGV_LOG"
  [ "$output" = "1" ]
}
