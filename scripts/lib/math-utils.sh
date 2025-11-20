#!/bin/bash
#
# math-utils.sh - Mathematical utility functions for Hackintoshster
# Author: Mario Aldayuz (thenotoriousllama)
# Website: https://aldayuz.com
#
# This library provides mathematical utilities for CPU core calculations and version comparisons.
# Source this file: source "${SCRIPT_DIR}/scripts/lib/math-utils.sh"
#

# Mathematical validator to determine if a given integer is a power of two
# Uses bitwise AND operation: powers of 2 have exactly one bit set, so (n & (n-1)) equals zero
# Required for CPU core allocation since macOS performs better with power-of-2 core counts
# Parameters: $1 - Integer to validate
# Returns: 0 (success) if power of 2, 1 (failure) otherwise
is_power_of_2() {
  local n=$1
  ((n > 0 && (n & (n - 1)) == 0))
}

# Calculates the smallest power of two that is greater than or equal to input value
# Iteratively doubles starting from 1 until reaching or exceeding the target number
# Used to round up user-specified CPU cores to the nearest valid power-of-2 value
# Parameters: $1 - Target integer value
# Output: Next power of 2 (e.g., 5→8, 9→16)
next_power_of_2() {
  local n=$1
  local p=1
  while ((p < n)); do
    p=$((p * 2))
  done
  echo $p
}

# Semantic version comparison utility for determining if v1 >= v2
# Splits version strings on dots and compares each numeric component left-to-right
# Handles versions with different segment counts by treating missing parts as zero
# Used to check QEMU version compatibility for applying conditional device arguments
# Parameters:
#   $1 - First version string (e.g., "6.2.0")
#   $2 - Second version string (e.g., "6.1")
# Returns: 0 if v1 >= v2, 1 if v1 < v2
version_compare() {
  local v1=$1 v2=$2
  local IFS='.'
  local v1_parts=($v1) v2_parts=($v2)
  local max_len=$(( ${#v1_parts[@]} > ${#v2_parts[@]} ? ${#v1_parts[@]} : ${#v2_parts[@]} ))

  for ((i=0; i<max_len; i++)); do
    local v1_part=${v1_parts[i]:-0}
    local v2_part=${v2_parts[i]:-0}
    if (( v1_part > v2_part )); then
      return 0
    elif (( v1_part < v2_part )); then
      return 1
    fi
  done
  return 0
}

# Export functions for use in other scripts
export -f is_power_of_2
export -f next_power_of_2
export -f version_compare

