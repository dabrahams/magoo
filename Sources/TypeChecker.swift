// Part of the Carbon Language project, under the Apache License v2.0 with LLVM
// Exceptions. See /LICENSE for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

/// The type-checking algorithm and associated data.
struct TypeChecker {
  /// Type-checks `program`, creating an instance that reflects the result.
  init(_ program: ExecutableProgram) {
    self.program = program

    // Create "external parent links" for the AST in our parentXXX properties.
    for d in program.ast { registerParentage(d) }

    // Check the bodies of nominal types.
    for d in program.ast { checkNominalTypeBody(d) }

    // Check function signatures.
    for d in program.ast {
      if case .function(let f) = d {
        _ = typeOfName(declaredBy: f as Declaration)
      }
    }
    // Check top-level initializations
    for d in program.ast {
      if case .initialization(let i) = d { check(i) }
    }
    // Check function bodies.
    for d in program.ast {
      if case .function(let f) = d { checkBody(f) }
    }
  }

  /// The state of memoization of a computation, including an "in progress"
  /// state that allows us to detect dependency cycles.
  private enum Memo<T: Equatable>: Equatable {
    case beingComputed, final(T)
  }

  /// The program being typechecked.
  private let program: ExecutableProgram

  /// Mapping from alternative declaration to the choice in which it is defined.
  private var parentChoice = ASTDictionary<Alternative, ChoiceDefinition>()

  /// Mapping from variable declaration to the initialization in which it is
  /// defined.
  private var parentInitialization
    = ASTDictionary<SimpleBinding, Initialization>()

  /// Memoized result of computing the type of the expression consisting of the
  /// name of each declared entity.
  private var typeOfNameDeclaredBy
    = Dictionary<Declaration.Identity, Memo<Type>>()
  
  /// The set of initializations that have been completely typechecked.
  private var checkedInitializations = Set<Initialization.Identity>()

  /// Mapping from struct to the parameter tuple type that initializes it.
  private var initializerTuples = ASTDictionary<StructDefinition, TupleType>()

  /// Return type of function currently being checked, if any.
  private var returnType: Type?

  /// A record of the errors encountered during type-checking.
  var errors: ErrorLog = []
}

private extension TypeChecker {
  /// Adds an error at the site of `offender` to the error log, returning
  /// `Type.error` for convenience.
  @discardableResult
  mutating func error<Node: AST>(
    _ offender: Node, _ message: String , notes: [CompileError.Note] = []
  ) -> Type {
    errors.append(CompileError(message, at: offender.site, notes: notes))
    return .error
  }
}

private extension TypeChecker {
  /// Records references from child declarations to their enclosing parents.
  mutating func registerParentage(_ d: TopLevelDeclaration) {
    switch d {
    case let .choice(c):
      for a in c.alternatives { parentChoice[a] = c }
    case let .initialization(i):
      registerParent(in: i.bindings, as: i)
    case .struct, .function: ()
    }
  }

  /// Records references from variable declarations in children to the given
  /// parent initialization.
  mutating func registerParent(in children: Pattern, as parent: Initialization) {
    switch children {
    case .atom: return
    case let .variable(x): parentInitialization[x] = parent
    case let .tuple(x):
      for a in x { registerParent(in: a.payload, as: parent) }
    case let .functionCall(x):
      for a in x.arguments { registerParent(in: a.payload, as: parent) }
    case let .functionType(x):
      for a in x.parameters { registerParent(in: a.payload, as: parent) }
      registerParent(in: x.returnType, as: parent)
    }
  }

  /// Typechecks the body of `d` if it declares a nominal type, recording the
  /// types of any interior declarations in `self.types` (and any errors in
  /// `self.errors`).
  mutating func checkNominalTypeBody(_ d: TopLevelDeclaration) {
    // Note: when nominal types gain methods and/or initializations, we'll need to
    // change the name of this method because those must be checked later.
    switch d {
    case let .struct(s):
      for m in s.members { _ = typeOfName(declaredBy: m) }
    case let .choice(c):
      for a in c.alternatives {
        parentChoice[a] = c
        _ = typeOfName(declaredBy: a)
      }
    case .function, .initialization: ()
    }
  }

  /// Returns the that `e` evaluates to, or `Type.error` if `e` doesn't evaluate
  /// to a type.
  mutating func evaluate(_ e: TypeExpression) -> Type {
    let t = type(e.body)
    if !t.isMetatype {
      return error(e, "Not a type expression (value has type \(t))")
    }
    let v = evaluate(e.body)
    return Type(v)!
  }

  /// Returns the result of evaluating `e`, logging an error if `e` doesn't
  /// have a value that can be computed at compile-time.
  mutating func evaluate(_ e: Expression) -> Value {
    // Temporarily evaluating the easy subset of type expressions until we have
    // an interpreter.
    switch e {
    case let .name(v):
      if let r = Type(program.definition[v]!) {
        return r
      }
      UNIMPLEMENTED()
    case .memberAccess(_):
      UNIMPLEMENTED()
    case .index(target: _, offset: _, _):
      UNIMPLEMENTED()
    case let .integerLiteral(r, _):
      return r
    case let .booleanLiteral(r, _):
      return r
    case let .tupleLiteral(t):
      return t.fields(reportingDuplicatesIn: &errors)
        .mapFields { self.evaluate($0) }
    case .unaryOperator(_):
      UNIMPLEMENTED()
    case .binaryOperator(_):
      UNIMPLEMENTED()
    case .functionCall(_):
      UNIMPLEMENTED()
    case .intType:
      return Type.int
    case .boolType:
      return Type.bool
    case .typeType:
      return Type.type
    case let .functionType(f):
      // Evaluate `f.parameters` as a type expression so we'll get a diagnostic
      // if it isn't a type.
      let p = evaluate(TypeExpression(f.parameters)).tuple ?? .void
      return Type.function(
        parameterTypes: p, returnType: evaluate(f.returnType))
    }
  }

  /// Returns the type of the entity declared by `d`.
  ///
  /// - Requires: if `d` declares a binding, its type has already been memoized
  ///   or is declared as a type expression rather than with `auto`.
  mutating func typeOfName(declaredBy d: Declaration) -> Type {
    switch typeOfNameDeclaredBy[d.identity] {
    case .beingComputed:
      return error(d.name, "type dependency loop")
    case let .final(t):
      return t
    case nil: ()
    }

    typeOfNameDeclaredBy[d.identity] = .beingComputed

    let r: Type
    switch d {
    case is TypeDeclaration:
      r = .type

    case let x as SimpleBinding:
      if let e = x.type.expression {
        r = evaluate(e)
      }
      else {
        check(parentInitialization[x]!)
        if case let .final(r0) = typeOfNameDeclaredBy[d.identity]! { r = r0 }
        else { UNREACHABLE() }
      }

    case let x as FunctionDefinition:
      r = typeOfName(declaredBy: x)

    case let a as Alternative:
      let payload = evaluate(TypeExpression(a.payload))
      let payloadTuple = payload == .error ? .void : payload.tuple!
      r = .alternative(
        parent: ASTIdentity(of: parentChoice[a]!), payload: payloadTuple)

    case let x as StructMember:
      r = evaluate(x.type)

    default: UNREACHABLE() // All possible cases should be handled.
    }
    typeOfNameDeclaredBy[d.identity] = .final(r)
    return r
  }

  /// Returns the type of the value computed by `e`, logging errors if `e`
  /// doesn't typecheck.
  mutating func type(_ e: Expression) -> Type {
    switch e {
    case .name(let v):
      return typeOfName(declaredBy: program.definition[v]!)

    case let .functionType(f):
      let p = evaluate(TypeExpression(f.parameters))
      assert(p == .error || p.tuple != nil)
      _ = evaluate(f.returnType)
      return .type

    case .intType, .boolType, .typeType:
      return .type

    case .memberAccess(let e):
      return type(e)

    case let .index(target: base, offset: index, _):
      let baseType = type(base)
      guard case .tuple(let types) = baseType else {
        return error(base, "Can't index non-tuple type \(baseType)")
      }
      let indexType = type(index)
      guard indexType == .int else {
        return error(index, "Index type must be Int, not \(indexType)")
      }
      let indexValue = evaluate(index) as! Int
      if let r = types[indexValue] { return r }
      return error(
        index, "Tuple type \(types) has no value at position \(indexValue)")

    case .integerLiteral:
      return .int

    case .booleanLiteral:
      return .bool

    case let .tupleLiteral(t):
      return .tuple(
        t.fields(reportingDuplicatesIn: &errors).mapFields { type($0) })

    case let .unaryOperator(u):
      return type(u)

    case let .binaryOperator(b):
      return type(b)

    case .functionCall(let f):
      return type(f)
    }
  }

  /// Logs an error pointing at `source` unless `t` is a metatype.
  mutating func expectMetatype<Node: AST>(_ t: Type, at source: Node) {
    if !t.isMetatype {
      error(
        source,
        "Pattern in this context must match type values, not \(t) values")
    }
  }

  /// Logs an error unless the type of `e` is `t`.
  mutating func expectType(of e: Expression, toBe expected: Type) {
    let actual = type(e)
    if actual != expected {
      error(e, "Expected expression of type \(expected), not \(actual).")
    }
  }

  mutating func type(_ u: UnaryOperatorExpression) -> Type {
    switch u.operation.kind {
    case .MINUS:
      expectType(of: u.operand, toBe: .int)
      return .int
    case .NOT:
      expectType(of: u.operand, toBe: .bool)
      return .bool
    default:
      UNREACHABLE(u.operation.text)
    }
  }
  
  mutating func type(_ b: BinaryOperatorExpression) -> Type {
    switch b.operation.kind {
    case .EQUAL_EQUAL:
      expectType(of: b.rhs, toBe: type(b.lhs))
      return .bool

    case .PLUS, .MINUS:
      expectType(of: b.lhs, toBe: .int)
      expectType(of: b.rhs, toBe: .int)
      return .int

    case .AND, .OR:
      expectType(of: b.lhs, toBe: .bool)
      expectType(of: b.rhs, toBe: .bool)
      return .bool

    default:
      UNREACHABLE(b.operation.text)
    }
  }

  /// Returns the type of the value computed by `e`, logging errors if `e`
  /// doesn't typecheck.
  mutating func type(_ e: FunctionCall<Expression>) -> Type {
    let calleeType = type(e.callee)
    let argumentTypes = type(.tupleLiteral(e.arguments))
    switch calleeType {
    case let .function(parameterTypes: p, returnType: r):
      if argumentTypes != .tuple(p) {
        error(
          e.arguments,
          "argument types \(argumentTypes) do not match parameter types \(p)")
      }
      return r

    case let .alternative(parent: resultID, payload: payload):
      if argumentTypes != .tuple(payload) {
        error(
          e.arguments, "argument types \(argumentTypes)"
            + " do not match payload type \(payload)")
      }
      return .choice(resultID)

    case .type:
      let calleeValue = evaluate(TypeExpression(e.callee))
      guard case .struct(let s) = calleeValue else {
        return error(e.callee, "type \(calleeValue) is not callable.")
      }

      let initializerType = initializerParameters(s)

      if argumentTypes != .tuple(initializerType) {
        error(
          e.arguments, "argument types \(argumentTypes) do not match"
            + " required initializer parameters \(initializerType)")
      }
      return calleeValue

    default:
      return error(e.callee, "value of type \(calleeType) is not callable.")
    }
  }

  mutating func type(_ e: MemberAccessExpression) -> Type {
    let baseType = type(e.base)

    switch baseType {
    case let .struct(baseID):
      let s = baseID.structure
      if let m = s.members.first(where: { $0.name == e.member }) {
        return typeOfName(declaredBy: m)
      }
      return error(e.member, "struct \(s.name) has no member '\(e.member)'")

    case let .tuple(t):
      if let r = t[e.member] { return r }
      return error(e.member, "tuple type \(t) has no field '\(e.member)'")

    case .type:
      // Handle access to a type member, like a static member in C++.
      if case let .choice(id) = evaluate(TypeExpression(e.base)) {
        let c: ChoiceDefinition = id.structure
        return c[e.member].map { typeOfName(declaredBy: $0) }
          ?? error(
            e.member, "choice \(c.name) has no alternative '\(e.member)'")
      }
      // No other types have members.
      fallthrough
    default:
      return error(
        e.base, "expression of type \(baseType) does not have named members")
    }
  }

  private mutating func checkBody(_ f: FunctionDefinition) {

  }
  
  /// Returns the type of the function declared by `f`, logging any errors in
  /// its signature, and, if `f` was declared with `=>`, in its body expression.
  private mutating func typeOfName(declaredBy f: FunctionDefinition) -> Type {
    // Make sure we don't bypass memoization.
    if typeOfNameDeclaredBy[f.identity] != .beingComputed {
      return typeOfName(declaredBy: f as Declaration)
    }

    let parameterTypes = f.parameters.fields(reportingDuplicatesIn: &errors)
      .mapFields { patternType($0) }

    let returnType: Type
    if case .expression(let t) = f.returnType {
      returnType = evaluate(t)
    }
    else if case .some(.return(let e, _)) = f.body {
      returnType = type(e)
    }
    else { UNREACHABLE("auto return type without return statement body") }

    return .function(parameterTypes: parameterTypes, returnType: returnType)
  }

  /// Returns the type matched by `p`, using `rhs`, if supplied, to deduce `auto`
  /// types, and logging any errors.
  ///
  /// - Note: DOES NOT verify that `rhs` is a subtype of the result; you must
  ///   check that separately.
  mutating func patternType(
    _ p: Pattern, initializerType rhs: Type? = nil) -> Type
  {
    switch (p) {
    case let .atom(e):
      return type(e)

    case let .variable(binding):
      let r = binding.type.expression.map { evaluate($0) }
        ?? rhs ?? error(
          binding.type, "No initializer available to deduce type for auto")
      typeOfNameDeclaredBy[binding.identity] = .final(r)
      return r
      // Hack for metatype subtyping---replace with real subtyping.
      // return rhs.map { r == .type && $0.isMetatype ? $0 : r } ?? r
      
    case let .tuple(t):
      return .tuple(
        t.fields(reportingDuplicatesIn: &errors).mapElements { (id, f) in
          patternType(f, initializerType: rhs?.tuple?.elements[id])
        })

    case let .functionCall(c):
      return patternType(c, initializerType: rhs)

    case let .functionType(f):
      return patternType(f, initializerType: rhs?.function)
    }
  }

  /// Returns the type matched by `p`, using `rhs`, if supplied, to deduce `auto`
  /// types, and logging any errors.
  ///
  /// - Note: DOES NOT verify that `rhs` is a subtype of the result; you must
  ///   check that separately.
  mutating func patternType(
    _ p: TupleSyntax<Pattern>, initializerType rhs: TupleType?,
    requireMetatype: Bool = false
  ) -> Type {
    return .tuple(
      p.fields(reportingDuplicatesIn: &errors).mapElements { (id, f) in
        let t = patternType(f, initializerType: rhs?.elements[id])
        if requireMetatype { expectMetatype(t, at: f) }
        return t
      })
  }

  // FIXME: There is significant code duplication between pattern and expression
  // type deduction.  Perhaps upgrade expressions to patterns and use the same
  // code to check?

  /// Returns the type matched by `p`, using `rhs`, if supplied, to deduce `auto`
  /// types, and logging any errors.
  ///
  /// - Note: DOES NOT verify that `rhs` is a subtype of the result; you must
  ///   check that separately.
  mutating func patternType(
    _ p: FunctionCall<Pattern>, initializerType rhs: Type?) -> Type
  {
    // Because p is a pattern, it must be a destructurable thing containing
    // bindings, which means the callee can only be a choice alternative
    // or struct type.
    let calleeType = type(p.callee)

    switch calleeType {
    case .type:
      let calleeValue = Type(evaluate(p.callee))!

      guard case .struct(let resultID) = calleeValue else {
        return error(
          p.callee, "Called type must be a struct, not '\(calleeValue)'.")
      }
      let parameterTypes = initializerParameters(resultID)
      let argumentTypes = patternType(p.arguments, initializerType: parameterTypes).tuple!

      if argumentTypes != parameterTypes {
        error(
          p.arguments,
          "Argument tuple type \(argumentTypes) doesn't match"
            + " struct initializer type \(parameterTypes)")
      }
      return calleeValue

    case let .alternative(parent: resultID, payload: payload):
      let argumentTypes = patternType(p.arguments, initializerType: payload).tuple!
      if argumentTypes != payload {
        error(
          p.arguments,
          "Argument tuple type \(argumentTypes) doesn't match"
            + " alternative payload type \(payload)")
      }
      return .choice(resultID)

    default:
      return error(p.callee, "instance of type \(calleeType) is not callable.")
    }
  }

  /// Ensures that `i` has been type-checked.
  mutating func check(_ i: Initialization) {
    if checkedInitializations.contains(i.identity) { return }
    defer { checkedInitializations.insert(i.identity) }
    
    let rhs = type(i.initializer)
    let lhs = patternType(i.bindings, initializerType: rhs)
    if lhs != rhs {
      error(i, "Pattern type \(lhs) does not match initializer type \(rhs).")
    }
  }

  /// Returns the initializer parameter list for the given struct
  mutating func initializerParameters(
    _ s: ASTIdentity<StructDefinition>
  ) -> TupleType {
    if let r = initializerTuples[s.structure] { return r }
    let r = s.structure.initializerTuple.fields(reportingDuplicatesIn: &errors)
      .mapFields { evaluate($0) }
    initializerTuples[s.structure] = r
    return r
  }

  /// Returns the type matched by `p`, using `rhs`, if supplied, to deduce `auto`
  /// types, and logging any errors.
  ///
  /// - Note: DOES NOT verify that `rhs` is a subtype of the result; you must
  ///   check that separately.
  mutating func patternType(
    _ t: FunctionType<Pattern>,
    initializerType rhs: (parameterTypes: TupleType, returnType: Type)?
  ) -> Type {
    _ = patternType(
      t.parameters, initializerType: rhs?.parameterTypes,
      requireMetatype: true)

    let r = patternType(t.returnType, initializerType: rhs?.returnType)
    expectMetatype(r, at: t.returnType)
    return .type
  }
}

/// A marker for code that needs to be implemented.  Eventually all of these
/// should be eliminated from the codebase.
func UNIMPLEMENTED(
  _ message: String? = nil, filePath: StaticString = #filePath,
  line: UInt = #line) -> Never {
  fatalError(message ?? "unimplemented", file: (filePath), line: line)
}

/// A marker for code that should never be reached.
func UNREACHABLE(
  _ message: String? = nil,
  filePath: StaticString = #filePath, line: UInt = #line) -> Never {
  fatalError(message ?? "unreachable", file: (filePath), line: line)
}
