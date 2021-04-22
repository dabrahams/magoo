// Part of the Carbon Language project, under the Apache License v2.0 with LLVM
// Exceptions. See /LICENSE for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import XCTest
@testable import CarbonInterpreter
import Foundation

extension String {
  /// Returns `self`, parsed as Carbon.
  func parsedAsCarbon(fromFile sourceFile: String = #filePath, tracing: Bool = false) throws
    -> [TopLevelDeclaration]
  {
    let p = CarbonParser()
    p.isTracingEnabled = tracing
    for t in Tokens(in: self, from: sourceFile) {
      try p.consume(token: t, code: t.kind)
    }
    return try p.endParsing()
  }
}

final class ParserTests: XCTestCase {
  func testInit() {
    // Make sure we can even create one.
    _ = CarbonParser()
  }

  let o = ASTSite.empty
  
  func testBasic0() {
    // Parse a few tiny programs
    guard let p = CheckNoThrow(try "fn main() -> Int;".parsedAsCarbon())
    else { return }
    
    XCTAssertEqual(
      p,
      [
        .function(
          FunctionDefinition(
            name: Identifier(text: "main", site: o),
            parameters: Tuple([], o),
            returnType: .intType(o),
            body: nil,
            site: o))])
  }

  func testBasic1() {
    guard let p = CheckNoThrow(try "fn main() -> Int {}".parsedAsCarbon())
    else { return }
    
    XCTAssertEqual(
      p,
      [
        .function(
          FunctionDefinition(
            name: Identifier(text: "main", site: o),
            parameters: Tuple([], o),
            returnType: .intType(o),
            body: .block([], o),
            site: o))])
  }

  func testBasic2() {
    guard let p = CheckNoThrow(try "var Int: x = 0;".parsedAsCarbon())
    else { return }
    
    XCTAssertEqual(
      p,
      [
        .initialization(
          Initialization(
            bindings: .variable(
              SimpleBinding(
                type: .literal(.intType(o)),
                name: Identifier(text: "x", site: o))),
            initializer: .integerLiteral(0, o),
            site: o))])
  }

  func testParseFailure() {
    XCTAssertThrowsError(try "fn ()".parsedAsCarbon()) { e in
      print(e)
      XCTAssertTrue(
        e is _CitronParserUnexpectedTokenError<Token, TokenID>);
    }

    XCTAssertThrowsError(try "fn f".parsedAsCarbon()) { e in
      XCTAssertTrue(e is CitronParserUnexpectedEndOfInputError);
    }
  }

  func testExamples() {
    let testdata = 
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("testdata")

    for f in try! FileManager().contentsOfDirectory(atPath: testdata.path) {
      let p = testdata.appendingPathComponent(f).path

      // Skip experimental syntax for now.
      if f.hasPrefix("experimental_") { continue }

      if f.hasSuffix("_fail.6c") {
        let s = try! String(contentsOfFile: p)
        XCTAssertThrowsError(try s.parsedAsCarbon(fromFile: p))
      }
      else {
        XCTAssertNoThrow(
          try String(contentsOfFile: p).parsedAsCarbon(fromFile: p))
      }
    }
  }
}
