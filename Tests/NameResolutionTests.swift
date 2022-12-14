// Part of the Carbon Language project, under the Apache License v2.0 with LLVM
// Exceptions. See /LICENSE for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import XCTest
@testable import CarbonInterpreter
import Foundation

final class NameResolutionTests: XCTestCase {
  func testNoMain() {
    let ast = "var x: Int = 1;".checkParsed()
    let n = NameResolution(ast)
    XCTAssertEqual(n.definition.count, 0)
    XCTAssertEqual(n.errors, [])
  }

  func testUndeclaredName0() {
    let ast = "var x: Y = 1;".checkParsed()
    let n = NameResolution(ast)
    XCTAssertEqual(n.definition.count, 0)
    n.errors.checkForMessageExcerpt("Un-declared name 'Y'")
  }

  func testDeclaredNameUse() {
    let ast = """
      var x: Int = 1;
      var y: Int = x;
      """.checkParsed()
    let n = NameResolution(ast)
    XCTAssertEqual(n.definition.count, 1)
    XCTAssertEqual(n.errors, [])
  }

  func testOrderIndependence() {
    let ast = """
      var y: Int = x;
      var x: Int = 1;
      """.checkParsed()
    let n = NameResolution(ast)
    XCTAssertEqual(n.definition.count, 1)
    XCTAssertEqual(n.errors, [])
  }

  func testScopeEnds() {
    let ast = """
      struct X { var a: Int; }
      var y: Int = a;
      """.checkParsed()
    let n = NameResolution(ast)
    n.errors.checkForMessageExcerpt("Un-declared name 'a'")
  }

  func testRedeclaredMember() {
    let ast = """
      struct X {
        var a: Int;
        var a: Bool;
      }
      """.checkParsed()
    let n = NameResolution(ast)
    n.errors.checkForMessageExcerpt("'a' already defined")
  }

  func testSelfReference() {
    let ast = """
      struct X {
        var a: Int;
        var b: fnty ()->X;
      }
      """.checkParsed()
    let n = NameResolution(ast)
    XCTAssertEqual(n.definition.count, 1)
    XCTAssertEqual(n.errors, [])
  }

  func testRedeclaredAlternative() {
    let ast = """
      choice X {
        Box,
        Car(Int),
        Children(Int, Bool),
        Car
      }
      """.checkParsed()
    let n = NameResolution(ast)
    n.errors.checkForMessageExcerpt("'Car' already defined")
  }

  func testExamples() throws {
    let testdata = 
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("testdata")

    for f in try! FileManager().contentsOfDirectory(atPath: testdata.path) {
      let p = testdata.appendingPathComponent(f).path

      // Skip experimental syntax for now.
      if f.hasPrefix("experimental_") { continue }

      if !f.hasSuffix("_fail.carbon") {
        _ = try String(contentsOfFile: p).checkNameResolution(fromFile: p)
      }
    }
  }
}
