#!/usr/bin/env bats
load test_helper

@test "mtr-test-suite.sh exists and is executable" {
  [ -x "$PROJECT_ROOT/mtr-test-suite.sh" ]
}

@test "dry-run exits 0" {
  run bash "$PROJECT_ROOT/mtr-test-suite.sh" --dry-run --no-summary
  assert_success
}

@test "--list-types prints test types" {
  run bash "$PROJECT_ROOT/mtr-test-suite.sh" --list-types
  assert_success
  assert_output --partial "ICMP4"
}

@test "--list-rounds prints rounds" {
  run bash "$PROJECT_ROOT/mtr-test-suite.sh" --list-rounds
  assert_success
  assert_output --partial "Standard"
}

@test "--version prints version" {
  run bash "$PROJECT_ROOT/mtr-test-suite.sh" --version
  assert_success
  assert_output --partial "v1.1.0"
}

@test "--help shows usage" {
  run bash "$PROJECT_ROOT/mtr-test-suite.sh" --help
  assert_success
  assert_output --partial "Usage"
}
