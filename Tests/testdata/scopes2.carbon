// Part of the Carbon Language project, under the Apache License v2.0 with LLVM
// Exceptions. See /LICENSE for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

fn main() -> Int {
  var n: auto = 0;
  while (not(n == 2)) {
    n = n + 1;
    match (n) {
      case 1 => continue;
      case 2 => break;
    }
  }
  return 0;
}
