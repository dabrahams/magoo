// Part of the Carbon Language project, under the Apache License v2.0 with LLVM
// Exceptions. See /LICENSE for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import XCTest
@testable import CarbonInterpreter

final class TypeCheckNominalTypeDeclaration: XCTestCase {

  func testStruct() {
    "struct X { var y: Int; }".checkTypeChecks()
  }

  func testStructStructMember() {
    """
    struct X { var y: Int; }
    struct Z { var a: X; }
    """.checkTypeChecks()
  }

  func testStructNonTypeExpression0()  {
    "struct X { var y: 42; }".checkFailsToTypeCheck(
      withMessage: "Not a type expression (value has type Int)")
  }

  func testChoice() {
    """
    choice X {
      Box,
      Car(Int),
      Children(Int, Bool)
    }
    """.checkTypeChecks()
  }

  func testChoiceChoiceMember() {
    """
    choice Y {
      Fork, Knife(X), Spoon(X, X)
    }
    choice X {
      Box,
      Car(Int),
      Children(Int, Bool)
    }
    """.checkTypeChecks()
  }

  func testChoiceNonTypeExpression() {
    "choice X { Bog(42) }".checkFailsToTypeCheck(
      withMessage: "Not a type expression (value has type (Int))")
  }
}

/// Tests that go along with having implemented checking of nominal type bodies
/// and function signatures.
final class TypeCheckFunctionSignatures: XCTestCase {
  //
  // Simplest test cases.
  //

  func testTrivial() {
    "fn f() {}".checkTypeChecks()
  }

  func testOneParameter() {
    "fn f(x: Int) {}".checkTypeChecks()
  }

  func testOneResult() {
    "fn f() -> Int { return 3; }".checkTypeChecks()
  }

  func testDoubleArrow() {
    "fn f() => 3;".checkTypeChecks()
  }

  func testDoubleArrowIdentity() {
    "fn f(x: Int) => x;".checkTypeChecks()
  }

  func testDuplicateLabel() {
    "fn f(.x = x: Int, .x = y: Int) => x;".checkFailsToTypeCheck(
      withMessage: "Duplicate label x")
  }

  func testEvaluateTupleLiteral() {
    "fn f(x: (Int, Int)) => (x, x);".checkTypeChecks()
  }

  func testEvaluateFunctionType() {
    """
    fn g(a: Int, b: Int)->Int { return a; }
    fn f(x: fnty (Int, Int)->Int) => x;
    fn h() => f(g)(3, 4);
    """.checkTypeChecks()
  }

  func testFunctionCallArityMismatch() {
    """
    fn g(a: Int, b: Int) => a;
    fn f(x: Bool) => g(x);
    """.checkFailsToTypeCheck(
      withMessage:
        "argument types (Bool) do not match parameter types (Int, Int)")
  }

  func testFunctionCallParameterTypeMismatch() {
    """
    fn g(a: Int, b: Int) => a;
    fn f(x: Bool) => g(1, x);
    """.checkFailsToTypeCheck(
      withMessage:
        "argument types (Int, Bool) do not match parameter types (Int, Int)")
  }

  func testFunctionCallLabelMismatch() {
    """
    fn g(.first = a: Int, b: Int) => a;
    fn f(x: Bool) => g(.last = 1, 2);
    """.checkFailsToTypeCheck(
      withMessage:
        "argument types (.last = Int, Int) "
        + "do not match parameter types (.first = Int, Int)")
  }

  func testFunctionCallLabel() {
    """
    fn g(.first = a: Int, .second = b: Int) => a;
    fn f(x: Bool) => g(.first = 1, .second = 2);
    """.checkTypeChecks()
  }

  func testAlternativePayloadMismatches() {
    """
    choice X { One }
    fn f() => X.One(1);
    """.checkFailsToTypeCheck(withMessage:"do not match payload type")

    """
    choice X { One(Int) }
    fn f() => X.One();
    """.checkFailsToTypeCheck(withMessage:"do not match payload type")

    """
    choice X { One(.x = Int) }
    fn f() => X.One(1);
    """.checkFailsToTypeCheck(withMessage:"do not match payload type")

    """
    choice X { One(Int) }
    fn f() => X.One(.x = 1);
    """.checkFailsToTypeCheck(withMessage:"do not match payload type")
  }

  func testSimpleTypeTypeExpressions() {
    """
    fn f() => Int;
    fn g(_: Type) => 1;
    fn h() => g(f());
    """.checkTypeChecks()

    """
    fn f() => Bool;
    fn g(_: Type) => 1;
    fn h() => g(f());
    """.checkTypeChecks()

    """
    fn f() => Type;
    fn g(_: Type) => 1;
    fn h() => g(f());
    """.checkTypeChecks()

    """
    fn f() => fnty (Int)->Int;
    fn g(_: Type) => 1;
    fn h() => g(f());
    """.checkTypeChecks()

    """
    struct X {}
    fn f() => X;
    fn g(_: Type) => 1;
    fn h() => g(f());
    """.checkTypeChecks()

    """
    choice X { Bob }
    fn f() => X;
    fn g(_: Type) => 1;
    fn h() => g(f());
    """.checkTypeChecks()
  }

  func testBooleanLiteral() {
    // This test was worth one line of coverage at some point.
    """
    fn f() => false;
    """.checkTypeChecks()
  }

  //
  // Exercising code paths that return the type of a declared entity.
  //

  func testDeclaredTypeStruct() {
    """
    struct X {}
    fn f() -> X { return X(); }
    fn g(X) {}
    """.checkTypeChecks()
  }

  func testDeclaredTypeChoice() {
    """
    choice X { Bonk }
    fn f() -> X { return X.Bonk; }
    fn g(X) {}
    """.checkTypeChecks()
  }

  func testDeclaredTypeAlternative() {
    """
    choice X { Bonk(Int) }
    fn f() => X.Bonk(3);
    """.checkTypeChecks()
  }

  func testDeclaredTypeFunctionDefinition() {
    """
    fn g() => f();
    fn f() => 1;
    """.checkTypeChecks()
  }

  func testNonStructTypeValueIsNotCallable() {
    """
    choice X { One(Int) }
    fn f() => X();
    """.checkFailsToTypeCheck(withMessage:"type X is not callable.")

    "fn f() => Int();".checkFailsToTypeCheck(
      withMessage: "type Int is not callable.")

    "fn f() => Bool();".checkFailsToTypeCheck(
      withMessage: "type Bool is not callable.")

    "fn f() => Type();".checkFailsToTypeCheck(
      withMessage: "type Type is not callable.")

    "fn f() => (fnty ()->Int)();".checkFailsToTypeCheck(
      withMessage: "type fnty () -> Int is not callable.")
  }

  func testTypeOfStructConstruction() {
    """
    struct X {}
    fn f(_: X) => 1;
    fn g() => f(X());
    """.checkTypeChecks()
  }

  func testStructConstructionArgumentMismatch() {
    """
    struct X {}
    fn f() => X(1);
    """.checkFailsToTypeCheck(withMessage:
        "argument types (Int) do not match required initializer parameters ()")
  }

  func testNonCallableNonTypeValues() {
    "fn f() => false();".checkFailsToTypeCheck(
      withMessage:"value of type Bool is not callable.")

    "fn f() => 1();".checkFailsToTypeCheck(
      withMessage:"value of type Int is not callable.")

    """
    struct X {}
    fn f() => X()();
    """.checkFailsToTypeCheck(withMessage:"value of type X is not callable.")
  }

  func testStructMemberAccess() {
    """
    struct X { var a: Int; var b: Bool; }
    fn f(y: X) => (y.a, y.b);
    """.checkTypeChecks()
  }

  func testTupleNamedAccess() {
    """
    fn f() => (.x = 0, .y = false).x;
    fn g() => (.x = 0, .y = false).y;
    """.checkTypeChecks()
  }

  func testInvalidMemberAccesses() {
    "fn f() => (.x = 0, .y = false).c;".checkFailsToTypeCheck(
      withMessage: "tuple type (.x = Int, .y = Bool) has no field 'c'")

    """
    struct X { var a: Int; var b: Bool; }
    fn f(y: X) => (y.a, y.c);
    """.checkFailsToTypeCheck(withMessage:"struct X has no member 'c'")

    """
    choice X {}
    fn f() => X.One();
    """.checkFailsToTypeCheck(withMessage:"choice X has no alternative 'One'")

    "fn f() => Int.One;".checkFailsToTypeCheck(
      withMessage: "expression of type Type does not have named members")

    "fn f() => 1.One;".checkFailsToTypeCheck(
      withMessage: "expression of type Int does not have named members")
  }

  func testTuplePatternType() {
    """
    fn f((1, x: Int), y: Bool) => x;
    fn g() => f((1, 2), true);
    """.checkTypeChecks()
  }

  func testFunctionCallPatternType() {
    """
    choice X { One(Int, Bool), Two }
    fn f(X.One(a: Int, b: Bool), X.Two()) => b;
    fn g(_: Bool) => 1;
    fn h() => g(f(X.One(3, true), X.Two()));
    """.checkTypeChecks()

    """
    struct X { var a: Int; var b: Bool; }
    fn f(X(.a = a: Int, .b = b: Bool)) => b;
    fn g(_: Bool) => 1;
    fn h() => g(f(X(.a = 3, .b = false)));
    """.checkTypeChecks()

    "fn f(Int(_: Bool));".checkFailsToTypeCheck(
      withMessage: "Called type must be a struct, not 'Int'")

    """
    struct X { var a: Int; var b: Bool; }
    fn f(X(.a = a: Bool, .b = b: Bool)) => b;
    """.checkFailsToTypeCheck(withMessage:
      "Argument tuple type (.a = Bool, .b = Bool) doesn't match"
        + " struct initializer type (.a = Int, .b = Bool)")

    """
    choice X { One(Int, Bool), Two }
    fn f(X.One(a: Bool, b: Bool), X.Two()) => b;
    """.checkFailsToTypeCheck(withMessage:
      "Argument tuple type (Bool, Bool) doesn't match"
        + " alternative payload type (Int, Bool)")

    """
    fn f(1(_: Bool));
    """.checkFailsToTypeCheck(withMessage:
      "instance of type Int is not callable")
  }

  func testFunctionTypePatternType() {
    "fn f(fnty(x: Type)) => 0;".checkTypeChecks()

    "fn f(fnty(x: Type)->Bool) => 0;".checkTypeChecks()

    "fn f(fnty(x: Type)->y: Type) => 0;".checkTypeChecks()

    "fn f(fnty(Int)->y: Type) => 0;".checkTypeChecks()

    "fn f(y: fnty(4)->Type) => 0;".checkFailsToTypeCheck(
      withMessage: "Not a type expression (value has type (Int))")

    "fn f(fnty(x: Int)) => 0;".checkFailsToTypeCheck(
      withMessage:
        "Pattern in this context must match type values, not Int values")

    "fn f(fnty(x: auto)) => 0;".checkFailsToTypeCheck(
      withMessage: "No initializer available to deduce type for auto")

    // A tuple of types is a valid type.
    "fn f(fnty(x: (Type, Type))->y: Type) => 0;".checkTypeChecks()

    "fn f(fnty(x: (Int, Int))->y: Type) => 0;".checkFailsToTypeCheck(
      withMessage:
        "Pattern in this context must match type values, not (Int, Int) values")

    """
    fn g(x: Int) => Int;
    fn f(fnty(x: (Int, Int))->g(3)) => 0;
    """.checkFailsToTypeCheck(
      withMessage:
        "Pattern in this context must match type values, not (Int, Int) values")
  }
}

/// Tests that go along with having implemented typechecking of initializations
/// at global scope.
final class TypeCheckTopLevelInitializations: XCTestCase {
  func testSimpleInitializer() {
    """
    var x: Int = 1;
    var y: Int = x;
    """.checkTypeChecks()

    """
    var y: Int = x;
    var x: Int = 1;
    """.checkTypeChecks()

    """
    var x: auto = 1;
    var y: Int = x;
    """.checkTypeChecks()

    """
    var y: Int = x;
    var x: auto = 1;
    """.checkTypeChecks()

    """
    var x: auto = true;
    var y: Int = x;
    """.checkFailsToTypeCheck(
      withMessage: "Pattern type Int does not match initializer type Bool")
  }

  func testTuplePatternInitializer() {
    """
    var ((1, x: Int), y: Bool) = ((1, 2), true);
    var a: (Int, Bool) = (x, y);
    """.checkTypeChecks()

    """
    var ((1, x: Int), y: auto) = ((1, 2), true);
    var a: (Int, Bool) = (x, y);
    """.checkTypeChecks()
  }

  func testFunctionCallPatternInitializer() {
    """
    choice X { One(Int, Bool), Two }
    var (X.One(a: Int, b: Bool), X.Two()) = (X.One(3, true), X.Two());
    """.checkTypeChecks()
    
    """
    choice X { One(Int, Bool), Two }
    var X.One(a: Int, b: auto) = X.One(3, true);
    """.checkTypeChecks()

    """
    choice X { One(Int, (Bool, Int)), Two }
    var (X.One(a: Int, (b: auto, 4)), X.Two()) = (X.One(3, (true, 4)), X.Two());
    """.checkTypeChecks()

    """
    struct X { var a: Int; var b: Bool; }
    var X(.a = a: Int, .b = b: Bool) = X(.a = 3, .b = false);
    """.checkTypeChecks()

    """
    struct X { var a: Int; var b: Bool; }
    var X(.a = a: auto, .b = b: Bool) = X(.a = 3, .b = false);
    """.checkTypeChecks()

    "var Int(_: Bool) = 1;".checkFailsToTypeCheck(
      withMessage: "Called type must be a struct, not 'Int'")

    """
    struct X { var a: Int; var b: Bool; }
    var X(.a = a: Bool, .b = b: Bool) = X(.a = 3, .b = true);
    """.checkFailsToTypeCheck(withMessage:
      "Argument tuple type (.a = Bool, .b = Bool) doesn't match"
        + " struct initializer type (.a = Int, .b = Bool)")

    """
    choice X { One(Int, Bool), Two }
    var (X.One(a: Bool, b: Bool), X.Two()) = (X.One(5, true), X.Two);
    """.checkFailsToTypeCheck(withMessage:
      "Argument tuple type (Bool, Bool) doesn't match"
        + " alternative payload type (Int, Bool)")

    """
    var 1(_: Bool) = 1;
    """.checkFailsToTypeCheck(withMessage:
      "instance of type Int is not callable")
  }

  func testFunctionTypeInitializer() {
    """
    fn g(_: Int)->Bool{}
    var y: fnty(Int)->Bool = g;
    """.checkTypeChecks()
  }

  func testFunctionTypePatternInitializer() {
    "var fnty(x: Type) = fnty(Int);".checkTypeChecks()

    "var fnty(x: Type)->Bool = fnty(Int)->Bool;".checkTypeChecks()

    // This one typechecks but will have to trap at runtime because the return
    // types don't match.

    "var fnty(x: Type)->Type = fnty(Int)->Int;".checkTypeChecks()

    // Same with this one; in both cases the return type of the rhs is a runtime
    // expression.  However, we have not implemented the compile-time evaluation
    // of variables yet.  This case would hit an UNIMPLEMENTED() call.  It is
    // rejected by the C++ implementation's typechecker because it expects all
    // type expressions (like `t` in the 2nd line) to be computed at
    // compile-time.  Jeremy agrees that's a bug.
    /*
    """
    var t: auto = Int;
    var fnty(x: Type)->Type = fnty(Int)->t;
    """.checkTypeChecks()
    */

    "var fnty(Int)->(y: Type) = fnty(Int)->Bool;".checkTypeChecks()

    "var y: fnty(4)->Type = fnty(Int)->Int;".checkFailsToTypeCheck(
      withMessage: "Not a type expression (value has type (Int))")

    "var fnty(x: Int) = fnty(Int);".checkFailsToTypeCheck(
      withMessage:
        "Pattern in this context must match type values, not Int values")

    "var fnty(x: auto) = 3;".checkFailsToTypeCheck(
      withMessage: "No initializer available to deduce type for auto")

    // A tuple of types is a valid type.
    """
    var fnty(x: (Type, Type))->y: Type
      = fnty((Int, Int))->Bool;
    """.checkTypeChecks()

    """
    var fnty(x: (Int, Int))->(y: Type)
      = fnty((Int, Int))->Bool;
    """.checkFailsToTypeCheck(
      withMessage:
        "Pattern in this context must match type values, not (Int, Int) values")

    """
    fn g(x: Int) => Int;
    var fnty(x: (Int, Int))->g(3)
       = fnty((Int, Int))->Bool;
    """.checkFailsToTypeCheck(
      withMessage:
        "Pattern in this context must match type values, not (Int, Int) values")
  }

  func testInvalidFunctionType() {
    "fn g(x: fnty(1)->Int) => x;".checkFailsToTypeCheck(
      withMessage: "Not a type expression (value has type (Int))")

    "fn g(x: fnty(Int)->true) => x;".checkFailsToTypeCheck(
      withMessage: "Not a type expression (value has type Bool)")
  }

  func DO_NOT_testInitializationsRequiringSubMetatypes() {
    // These tests require interesting metatypes and subtype relationships,
    // and are not supported by the C++ implementation either.
    "var fnty(x: auto) = fnty(Int);".checkTypeChecks()
    "var fnty(y: auto)->Bool = fnty(Int)->Bool;".checkTypeChecks()
    "var fnty(Int)->(z: auto) = fnty(Int)->Bool;".checkTypeChecks()
    """
    var fnty((Type, z: auto))->(y: Type)
      = fnty((Int, Int))->Bool;
    """.checkTypeChecks()
  }

  func DO_NOT_testBindingToCalleeStructType() {
    // This test requires parser/AST changes, and is not supported by the C++
    // implementation either.
    """
    struct X {}
    var  t0: auto () = X() // a
    var (t1: auto)() = X() // b
    """.checkTypeChecks()
  }
}

/// Tests of indexing and operator expression typechecking.
final class TypeCheckOperatorAndIndexExpressions: XCTestCase {
  func testIndexExpression() {
    "fn f(r: (Int,)) => r[0];".checkTypeChecks()

    """
    fn f(r: (Int, Bool)) => r[0];
    fn g(_: Int) => 1;
    fn h() => g(f((1, false)));
    """.checkTypeChecks()

    """
    fn f(r: (Int, Bool)) => r[1];
    fn g(_: Bool) => 1;
    fn h() => g(f((1, false)));
    """.checkTypeChecks()

    "fn f(x: Int) => x[0];".checkFailsToTypeCheck(
      withMessage:"Can't index non-tuple type Int")

    "fn f(x: (Int,)) => x[Int];".checkFailsToTypeCheck(
      withMessage: "Index type must be Int, not Type")

    "fn f(r: (.x = Int, Int, Bool)) => r[3];".checkFailsToTypeCheck(
      withMessage:
        "Tuple type (.x = Int, Int, Bool) has no value at position 3")
  }

  func testTypeOfUnaryOperator() {
    """
    fn f() => -3;
    fn g(_: Int) => 0;
    fn h() => g(f());
    """.checkTypeChecks("unary minus")

    """
    fn f() => not false;
    fn g(_: Bool) => 0;
    fn h() => g(f());
    """.checkTypeChecks("logical not")

    "fn f() => -false;".checkFailsToTypeCheck(withMessage:
      "Expected expression of type Int, not Bool")

    "fn f() => not 3;".checkFailsToTypeCheck(withMessage:
        "Expected expression of type Bool, not Int")
  }

  func testTypeOfBinaryOperator() {
    """
    fn f(a: Int, b: Int) => a == b;
    fn g(_: Bool) => 0;
    fn h() => g(f(1, 2));
    """.checkTypeChecks()

    """
    fn f(a: Int, b: Int) => a + b;
    fn g(_: Int) => 0;
    fn h() => g(f(1, 2));
    """.checkTypeChecks()

    """
    fn f(a: Int, b: Int) => a - b;
    fn g(_: Int) => 0;
    fn h() => g(f(1, 2));
    """.checkTypeChecks()

    """
    fn f(a: Bool, b: Bool) => a and b;
    fn g(_: Bool) => 0;
    fn h() => g(f(true, false));
    """.checkTypeChecks()

    """
    fn f(a: Bool, b: Bool) => a or b;
    fn g(_: Bool) => 0;
    fn h() => g(f(true, false));
    """.checkTypeChecks()
  }

  func testTypeDependencyLoop() {
    """
    fn f() => g();
    fn g() => f();
    """.checkFailsToTypeCheck(withMessage: "type dependency loop")
  }
}

/// Tests of statement typechecking.
final class TypeCheckStatements: XCTestCase {
  func testExpressionStatement() {
    """
    fn f(a: Bool, b: Int) {
      not a;
    }
    """.checkTypeChecks()

    """
    fn f(a: Bool, b: Int) {
      not b;
    }
    """.checkFailsToTypeCheck(
      withMessage: "Expected expression of type Bool, not Int")
  }

  func testInitialization() {
    """
    fn f(a: Bool, b: Int) -> Int {
      var x: auto = b;
      return x;
    }
    """.checkTypeChecks()

    """
    fn f(a: Bool, b: Int) -> Bool {
      var x: Bool = b;
      return x;
    }
    """.checkFailsToTypeCheck(
      withMessage: "Pattern type Bool does not match initializer type Int")
  }

  func testAssignment() {
    """
    fn f(b: Int) {
      var x: Int = b;
      x = b;
    }
    """.checkTypeChecks()

    """
    var x: Int = 3;
    fn f(a: Bool, b: Int) {
      x = b;
    }
    """.checkTypeChecks()

    """
    fn f(a: Bool) {
      var x: Int = 3;
      x = a;
    }
    """.checkFailsToTypeCheck(
      withMessage: "Expected expression of type Bool, not Int")

    """
    var x: Int = 3;
    fn f(a: Bool) {
      x = a;
    }
    """.checkFailsToTypeCheck(
      withMessage: "Expected expression of type Bool, not Int")
  }

  func testIf() {
    """
    fn f(b: Int) -> Bool {
      if (b == 0) {
        return true;
      }
      else {
        return false;
      }
    }
    """.checkTypeChecks()

    """
    fn f(b: Int) -> Bool {
      if (b == 0) {
        return true;
      }
      return false;
    }
    """.checkTypeChecks()

    """
    fn f(b: Int) -> Bool {
      if (b) {
        return true;
      }
      else {
        return false;
      }
    }
    """.checkFailsToTypeCheck(
      withMessage: "Expected expression of type Bool, not Int")

    """
    fn f(b: Int) -> Bool {
      if (b) {
        return true;
      }
      return false;
    }
    """.checkFailsToTypeCheck(
      withMessage: "Expected expression of type Bool, not Int")

    """
    fn f(b: Int) -> Int {
      if (b == 0) {
        return b;
      }
      else {
        return true;
      }
      return b;
    }
    """.checkFailsToTypeCheck(
      withMessage: "Expected expression of type Int, not Bool")

    """
    fn f(b: Int) -> Int {
      if (b == 0) {
        return true;
      }
      return b;
    }
    """.checkFailsToTypeCheck(
      withMessage: "Expected expression of type Int, not Bool")
  }

  func testWhile() {
    """
    fn f(b: Int) -> Int {
      while (not (b == 0)) {
        b = b - 1;
      }
      return b;
    }
    """.checkTypeChecks()

    """
    fn f(b: Int) -> Int {
      while (b) {
        b = b - 1;
      }
      return b;
    }
    """.checkFailsToTypeCheck(
      withMessage: "Expected expression of type Bool, not Int")

    """
    fn f(b: Int) -> Int {
      while (b) {
        b = not b;
      }
      return b;
    }
    """.checkFailsToTypeCheck(
      withMessage: "Expected expression of type Bool, not Int")
  }

  func testMatch() {
    """
    fn f(x: Int) -> Int {
      match (x) {
        case 5 =>
          return 0;
        default =>
          return 1;
      }
    }
    """.checkTypeChecks()

    """
    fn f(x: Int) -> Int {
      match (x) {
        case (Int, Int) =>
          return 0;
        default =>
          return 1;
      }
    }
    """.checkFailsToTypeCheck(
      withMessage: "Pattern type (Type, Type) incompatible"
        + " with matched expression type Int")

    """
    fn f(x: Int) -> Int {
      match (x) {
        case 5 =>
          return (false, false);
        default =>
          return 1;
      }
    }
    """.checkFailsToTypeCheck(
      withMessage: "Expected expression of type Int, not (Bool, Bool)")
  }

  func testBreak() {
    """
    fn f(b: Int) -> Int {
      while (not (b == 0)) {
        b = b - 1;
        if (b == 4) { break; }
      }
      return b;
    }
    """.checkTypeChecks()

    """
    fn f(b: Int) -> Int {
      while (not (b == 0)) {
        b = b - 1;
      }
      break;
      return b;
    }
    """.checkFailsToTypeCheck(
      withMessage: "invalid outside loop body")
  }

  func testContinue() {
    """
    fn f(b: Int) -> Int {
      while (not (b == 0)) {
        b = b - 1;
        if (b == 4) { continue; }
      }
      return b;
    }
    """.checkTypeChecks()

    """
    fn f(b: Int) -> Int {
      while (not (b == 0)) {
        b = b - 1;
      }
      continue;
      return b;
    }
    """.checkFailsToTypeCheck(
      withMessage: "invalid outside loop body")
  }
}

final class TypeCheckExamples: XCTestCase {
  func testExamples() throws {
    let testdata =
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("testdata")

    for f in try FileManager().contentsOfDirectory(atPath: testdata.path) {
      let sourcePath = testdata.appendingPathComponent(f).path

      // Skip experimental syntax for now.
      if f.hasPrefix("experimental_") { continue }

      let source = try String(contentsOfFile: sourcePath)
      if f.contains("pattern_variable_fail.carbon") || f.contains("tuple2_fail"){
        XCTAssertThrowsError(try source.parsedAsCarbon(fromFile: sourcePath))
      }
      else if f.contains("type_compute") {
        // Skip for now; we don't handle nontrivial type computation.
      }
      else if f.contains("_fail")
                || source.contains("Error expected.")
      // This file's error is about declaration order dependency, which we don't
      // enforce.
                && !f.contains("global_variable8.carbon")
      {
        source.checkFailsToTypeCheck(fromFile: sourcePath, withMessage: "")
      } else {
        source.checkTypeChecks(fromFile: sourcePath)
      }
    }
  }
}
