// Part of the Carbon Language project, under the Apache License v2.0 with LLVM
// Exceptions. See /LICENSE for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import XCTest
@testable import CarbonInterpreter

final class InterpreterTests: XCTestCase {
  func testMinimal0() {
    guard let exe = "fn main() -> Int { return 0; }".checkExecutable() else {
      return
    }

    var engine = Interpreter(exe)
    XCTAssertEqual(0, engine.run() as? Int)
  }

  func testMinimal1() {
    guard let exe = "fn main() -> Int { return 42; }".checkExecutable() else {
      return
    }

    var engine = Interpreter(exe)
    XCTAssertEqual(42, engine.run() as? Int)
  }

  func testExpressionStatement1() {
    guard let exe = "fn main() -> Int { 777; return 42; }".checkExecutable()
    else { return }
    var engine = Interpreter(exe)
    XCTAssertEqual(42, engine.run() as? Int)
  }

  func testExpressionStatement2() {
    guard let exe = "fn main() -> Int { var x: Int = 777; x + 1; return 42; }".checkExecutable()
    else { return }
    var engine = Interpreter(exe)
    XCTAssertEqual(42, engine.run() as? Int)
  }

  func run(_ testFile: String, tracing: Bool = false) -> Int? {
    let testdata =
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("testdata")

    let sourcePath = testdata.appendingPathComponent(testFile).path
    let source = try! String(contentsOfFile: sourcePath)

    // Useful during testing to see which test file is failing.
    // print("running", sourcePath)
    guard let program = source.checkExecutable(fromFile: sourcePath)
    else { return nil }
    var engine = Interpreter(program)
    engine.tracing = tracing
    return engine.run() as? Int
  }

  func DO_NOT_test1Interpreter() {
    // XCTAssertEqual(run("funptr1.carbon"), 0)
  }

  func testExamples() {
    XCTAssertEqual(run("assignment_copy1.carbon"), 0)
    XCTAssertEqual(run("assignment_copy2.carbon"), 0)
    XCTAssertEqual(run("block1.carbon"), 0)
    XCTAssertEqual(run("block2.carbon"), 0)
    XCTAssertEqual(run("break1.carbon"), 0)
    XCTAssertEqual(run("choice1.carbon"), 0)
    XCTAssertEqual(run("continue1.carbon"), 0)
    // XCTAssertEqual(run("experimental_continuation1.carbon"), 0)
    // XCTAssertEqual(run("experimental_continuation2.carbon"), 0)
    // XCTAssertEqual(run("experimental_continuation3.carbon"), 0)
    // XCTAssertEqual(run("experimental_continuation4.carbon"), 0)
    // XCTAssertEqual(run("experimental_continuation5.carbon"), 0)
    // XCTAssertEqual(run("experimental_continuation6.carbon"), 0)
    // XCTAssertEqual(run("experimental_continuation7.carbon"), 0)
    // XCTAssertEqual(run("experimental_continuation8.carbon"), 0)
    // XCTAssertEqual(run("experimental_continuation9.carbon"), 0)
    XCTAssertEqual(run("fun1.carbon"), 0)
    XCTAssertEqual(run("fun2.carbon"), 0)
    XCTAssertEqual(run("fun3.carbon"), 0)
    XCTAssertEqual(run("fun4.carbon"), 0)
    XCTAssertEqual(run("fun5.carbon"), 0)
    // XCTAssertEqual(run("fun6_fail_type.carbon"), 0)
    XCTAssertEqual(run("fun_named_params.carbon"), 0)
    XCTAssertEqual(run("fun_named_params2.carbon"), 0)
    XCTAssertEqual(run("fun_recur.carbon"), 0)
    XCTAssertEqual(run("funptr1.carbon"), 0)
    XCTAssertEqual(run("global_variable1.carbon"), 0)
    XCTAssertEqual(run("global_variable2.carbon"), 0)
    // Expect a type checking error.
    // XCTAssertEqual(run("global_variable3.carbon"), 0)
    XCTAssertEqual(run("global_variable4.carbon"), 0)
    // Expect a type checking error.
    // XCTAssertEqual(run("global_variable5.carbon"), 0)
    XCTAssertEqual(run("global_variable6.carbon"), 0)
    XCTAssertEqual(run("global_variable7.carbon"), 0)
    XCTAssertEqual(run("global_variable8.carbon"), 0)
    XCTAssertEqual(run("if1.carbon"), 0)
    XCTAssertEqual(run("if2.carbon"), 0)
    XCTAssertEqual(run("if3.carbon"), 0)
    XCTAssertEqual(run("match_any_int.carbon"), 0)
    XCTAssertEqual(run("match_int.carbon"), 0)
    XCTAssertEqual(run("match_int_default.carbon"), 0)
    // XCTAssertEqual(run("match_type.carbon"), 0)
    XCTAssertEqual(run("next.carbon"), 0)
    XCTAssertEqual(run("pattern_init.carbon"), 0)
    // XCTAssertEqual(run("pattern_variable_fail.carbon"), 0)
    XCTAssertEqual(run("record1.carbon"), 0)
    XCTAssertEqual(run("struct1.carbon"), 0)
    XCTAssertEqual(run("struct2.carbon"), 0)
    XCTAssertEqual(run("struct3.carbon"), 0)
    XCTAssertEqual(run("tuple1.carbon"), 0)
    XCTAssertEqual(run("tuple2.carbon"), 0)
    // XCTAssertEqual(run("tuple2_fail.carbon"), 0)
    XCTAssertEqual(run("tuple3.carbon"), 0)
    // TODO: This is now supposed to cause a type checking error?
    XCTAssertEqual(run("tuple4.carbon"), 0)
    // TODO: This is now supposed to cause a type checking error?
    XCTAssertEqual(run("tuple5.carbon"), 0)
    XCTAssertEqual(run("tuple_assign.carbon"), 0)
    // XCTAssertEqual(run("tuple_equality.carbon"), 0) // Expected type check error
    XCTAssertEqual(run("tuple_equality2.carbon"), 0)
    // XCTAssertEqual(run("tuple_equality3.carbon"), 0) // Expected type check error
    XCTAssertEqual(run("tuple_match.carbon"), 0)
    XCTAssertEqual(run("tuple_match2.carbon"), 0)
    XCTAssertEqual(run("tuple_match3.carbon"), 0)
    XCTAssertEqual(run("type_compute.carbon"), 0)
    XCTAssertEqual(run("type_compute2.carbon"), 0)
    XCTAssertEqual(run("type_compute3.carbon"), 0)
    XCTAssertEqual(run("while1.carbon"), 0)
    XCTAssertEqual(run("zero.carbon"), 0)
  }
}
