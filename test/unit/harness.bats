#!/usr/bin/env bats

load helpers

@test "harness: repo root is mounted and readable" {
  [ -f "$REPO_ROOT/Makefile" ]
}

@test "harness: bats can run a trivial assertion" {
  run bash -c 'echo hello'
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}
