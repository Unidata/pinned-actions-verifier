#!/usr/bin/env bash
# Copyright (c) 2026 University Corporation for Atmospheric Research/Unidata
# See LICENSE for license information.

# This script runs verify-action-sha.sh against test cases in tests/valid and tests/invalid.
# Tests in tests/valid are expected to return a 0 exit code.
# Tests in tests/invalid are expected to return a 1 exit code.

EXIT_CODE=0

run_tests() {
  local tests_dir="$1"
  local expected_exit_code="$2"

  echo "Running tests in: $tests_dir (expected exit code: $expected_exit_code)"
  for test_file in "$tests_dir"/*.yml; do
    echo "Running test for: $test_file"
    ./verify-action-sha.sh "$test_file"
    actual_exit_code=$?
    
    if [ $actual_exit_code -ne $expected_exit_code ]; then
      echo "  [FAIL] Test for $test_file failed. Expected $expected_exit_code, got $actual_exit_code."
      EXIT_CODE=1
    else
      echo "  [PASS] Test for $test_file passed."
    fi
    echo "----------------------------------------"
  done
}

# Run valid tests
run_tests "tests/valid" 0

# Run invalid tests
run_tests "tests/invalid" 1

if [ $EXIT_CODE -eq 0 ]; then
  echo "All tests passed!"
else
  echo "Some tests failed."
fi

exit $EXIT_CODE
