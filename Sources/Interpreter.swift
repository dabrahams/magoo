// Part of the Carbon Language project, under the Apache License v2.0 with LLVM
// Exceptions. See /LICENSE for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

/// A notional “self-returning function” type, to be used as a continuation.
///
/// Swift doesn't allow a recursive function type to be declared directly, but
/// we can indirect through `Onward`.
fileprivate typealias Next = (inout Interpreter)->Onward

/// A notional “self-returning function” type, to be returned from continuations.
///
/// Swift doesn't allow a recursive function type to be declared directly, but
/// we can indirect through this struct.
fileprivate struct Onward {

  /// Creates an instance with the semantics of `implementation`.
  init(_ code: @escaping Next) {
    self.code = code
  }

  /// Executes `self` in `context`.
  func callAsFunction(_ context: inout Interpreter) -> Onward {
    code(&context)
  }

  /// The underlying implementation.
  let code: Next
}

/// A continuation function that takes an input.
fileprivate typealias Consumer<T> = (T, inout Interpreter)->Onward

/// An operator for constructing a continuation result from a `Consumer<T>`
/// function and an input value.
infix operator => : DefaultPrecedence

/// Creates a continuation result notionally corresponding to `followup(x)`.
///
/// You can think of `a => f` or as a way of binding `a` to the argument of `f`
/// and coercing the result to `Onward`.
fileprivate func => <T>(x: T, followup: @escaping Consumer<T>) -> Onward {
  Onward { me in followup(x, &me) }
}

/// All the data that needs to be saved and restored across function call
/// boundaries.
fileprivate struct CallFrame {
  /// The locations of temporaries that persist to the ends of their scopes and
  /// thus can't be cleaned up in the course of expression evaluation.
  var persistentAllocations: Stack<Address> = .init()

  /// The set of all allocated temporary addresses, with an associated
  /// expression tag for diagnostic purposes.
  ///
  /// Used to ensure we don't forget to clean up temporaries when they are no
  /// longer used.
  var ephemeralAllocations: [Address: Expression] = [:]

  /// A mapping from local bindings to addresses.
  var locals: ASTDictionary<SimpleBinding, Address> = .init()

  /// The place where the result of this call is to be written.
  var resultAddress: Address

  /// The code to execute when this call exits
  var onReturn: Onward

  /// The code to execute when the current loop exits.
  var onBreak: Onward? = nil

  /// Code that returns to the top of the current loop, if any.
  var onContinue: Onward? = nil
}

/// The engine that executes the program.
struct Interpreter {
  /// The program being executed.
  fileprivate let program: ExecutableProgram

  /// The frame for the current function.
  fileprivate var frame: CallFrame

  /// Mapping from global bindings to address.
  fileprivate var globals: ASTDictionary<SimpleBinding, Address> = .init()

  /// Storage for all addressable values.
  fileprivate var memory = Memory()

  /// The next execution step.
  fileprivate var nextStep: Onward

  /// True iff the program is still running.
  fileprivate var running: Bool = true

  /// A record of any errors encountered.
  fileprivate var errors: ErrorLog = []

  /// True iff we are printing an evaluation trace to stdout
  public var tracing: Bool {
    get { traceLevel != nil }
    set { traceLevel = newValue ? traceLevel ?? 0 : nil }
  }

  /// If tracing, the indent level for logging.
  public var traceLevel: Int? = nil

  /// Mapping from expression to its static type.
  fileprivate var staticType: ASTDictionary<Expression, Type> {
    program.staticType
  }

  /// Creates an instance that runs `p`.
  ///
  /// - Requires: `p.main != nil`
  init(_ p: ExecutableProgram) {
    self.program = p

    frame = CallFrame(
      resultAddress: memory.allocate(boundTo: .int),
      onReturn: Onward { me in
        me.cleanUpPersistentAllocations(above: 0) { me in me.terminate() }
      })

    // First step runs the body of `main`
    nextStep = Onward { [main = program.main!] me in
      me.run(main.body!, then: me.frame.onReturn.code)
    }
  }

  /// Runs the program to completion and returns the result value, if any.
  mutating func run() -> Value? {
    while step() {}
    return memory[frame.resultAddress]
  }

  /// Creates an instance that evaluates `e` in the context of `ast`
  /// during `typeChecking`, in the context of the given `resolvedNames`.
  init(
    evaluating e: Expression, in parsedProgram: AbstractSyntaxTree,
    whileInProgress typeChecking: TypeChecker, resolvedNames: NameResolution
  ) {
    self.program = ExecutableProgram(
      parsedProgram, nameLookup: resolvedNames, typeChecking: typeChecking)

    frame = CallFrame(
      resultAddress: memory.allocate(boundTo: program.staticType[e]!),
      onReturn: Onward { me in
        fatalError("return in expression should be ruled out by parser")
      })

    nextStep = Onward { me in
      me.evaluate(e, into: me.frame.resultAddress) { _, me in me.terminate() }
    }
  }
}


fileprivate extension Interpreter {
  /// Advances execution by one unit of work, returning `true` iff the program
  /// is still running and `false` otherwise.
  mutating func step() -> Bool {
    if running {
      nextStep = nextStep(&self)
    }
    return running
  }

  /// Exits the running program.
  mutating func terminate() -> Onward {
    running = false
    return Onward { _ in fatalError("Terminated program can't continue.") }
  }

  /// Adds an error at the site of `offender` to the error log and marks the
  /// program as terminated.
  ///
  /// Returns a non-executable task for convenience.
  @discardableResult
  mutating func error<Node: AST>(
    _ offender: Node, _ message: String , notes: [CarbonError.Note] = []
  ) -> Onward {
    errors.append(CarbonError(message, at: offender.site, notes: notes))
    return terminate()
  }

  mutating func trace<Subject: AST>(
    _ subject: Subject, _ message: @autoclosure ()->String, indent: Int = 0,
    filePath: StaticString = #filePath, line: UInt = #line
  ) {
    trace_(
      subject.site, message(), indent: indent, level: &traceLevel,
      filePath: filePath, line: line)
  }

  func trace<Subject: AST>(
    _ subject: Subject, _ message: @autoclosure ()->String,
    filePath: StaticString = #filePath, line: UInt = #line
  ) {
    var t = traceLevel
    trace_(
      subject.site, message(), indent: 0, level: &t,
      filePath: filePath, line: line)
  }

  /// Accesses the value in `memory` at `a`, or halts the interpreted program
  /// with an error if `a` is not an initialized address, returning Type.error.
  subscript(a: Address) -> Value {
    memory[a]
  }
}

/// Running statements.
fileprivate extension Interpreter {
  /// Executes `s`, and then, absent interesting control flow,
  /// `proceed`.
  ///
  /// An example of interesting control flow is a return statement, which
  /// ignores any `proceed` and exits the current function instead.
  ///
  /// In fact this function only executes one “unit of work” and packages the
  /// rest of executing `s` (if any), and whatever follows that, into the
  /// returned `Onward`.
  mutating func run(_ s: Statement, then proceed: @escaping Next) -> Onward {
    trace(s, "running statement")
    sanityCheck(
      frame.ephemeralAllocations.isEmpty,
      "leaked \(frame.ephemeralAllocations)")

    switch s {
    case let .expressionStatement(e, _):
      return evaluate(e) { resultAddress, me in
        me.deleteAnyEphemeral(at: resultAddress, then: proceed)
      }

    case let .assignment(target: t, source: s, _):
      return evaluate(s) { source, me in
        me.trace(t, "assigning \(me[source]) from \(source)")
        return me.assign(t, from: source) { me in
          me.deleteAnyEphemeral(at: source, then: proceed)
        }
      }

    case let .initialization(i):
      // Storage must be allocated for the initializer value even if it's an
      // lvalue, so the vars bound to it have distinct values.  Because vars
      // will be bound to parts of the initializer and are mutable, it must
      // persist through the current scope.
      return allocate(i.initializer, mutable: true, persist: true) { rhsArea, me in
        me.evaluate(i.initializer, into: rhsArea) { rhs, me in
          me.match(
            i.bindings, toValueOfType: me.staticType[i.initializer]!, at: rhs)
          { matched, me in
            matched ? Onward(proceed) : me.error(
              i.bindings, "Initialization pattern not matched by \(me[rhs])")
          }
        }
      }

    case let .if(c, s0, else: s1, _):
      return evaluateAndConsume(c) { (condition: Bool, me) in
        if condition {
          return me.run(s0, then: proceed)
        }
        else {
          if let s1 = s1 { return me.run(s1, then: proceed) }
          else { return Onward(proceed) }
        }
      }

    case let .return(e, _):
      return evaluate(e, into: frame.resultAddress) { _, me in
        me.frame.onReturn(&me)
      }

    case let .block(children, _):
      return inScope(
        do: { me, proceed1 in me.runBlock(children[...], then: proceed1) },
        then: proceed)

    case let .while(condition, body, _):
      let savedLoopContext = (frame.onBreak, frame.onContinue)
      let mark=frame.persistentAllocations.count

      let onBreak = Onward { me in
        (me.frame.onBreak, me.frame.onContinue) = savedLoopContext
        return me.cleanUpPersistentAllocations(above: mark, then: proceed)
      }

      let onContinue = Onward { me in
        return me.cleanUpPersistentAllocations(above: mark) {
          $0.runWhile(condition, body, then: onBreak.code)
        }
      }

      (frame.onBreak, frame.onContinue) = (onBreak, onContinue)
      return onContinue(&self)

    case let .match(subject: e, clauses: clauses, _):
      return inScope(do: { me, proceed1 in
        me.allocate(e, persist: true) { subjectArea, me in
          me.evaluate(e, into: subjectArea) { subject, me in
            me.runMatch(e, at: subject, against: clauses[...], then: proceed1)
          }}}, then: proceed)

    case .break:
      return frame.onBreak!

    case .continue:
      return frame.onContinue!
    }
  }

  mutating func inScope(
    do body: (inout Self, @escaping Next)->Onward,
    then proceed: @escaping Next) -> Onward
  {
    let mark=frame.persistentAllocations.count
    return body(&self) { me in
      sanityCheck(
        me.frame.ephemeralAllocations.isEmpty,
        "leaked \(me.frame.ephemeralAllocations)")

      return me.cleanUpPersistentAllocations(above: mark, then: proceed)
    }
  }

  /// Executes the statements of `content` in order, then `proceed`.
  mutating func runBlock(
    _ content: ArraySlice<Statement>, then proceed: @escaping Next) -> Onward
  {
    content.isEmpty ? Onward(proceed) : run(content.first!) { me in
      me.runBlock(content.dropFirst(), then: proceed)
    }
  }

  mutating func runMatch(
    _ e: Expression, at subject: Address,
    against clauses: ArraySlice<MatchClause>,
    then proceed: @escaping Next) -> Onward
  {
    guard let clause = clauses.first else {
      return error(e, "no pattern matches \(self[subject])")
    }

    let onMatch = Onward { me in
      me.inScope(
        do: { me, proceed in me.run(clause.action, then: proceed) },
        then: proceed)
    }
    guard let p = clause.pattern else { return onMatch }

    return match(p, toValueOfType: staticType[e]!, at: subject) { matched, me in
      if matched { return onMatch }
      return me.runMatch(
        e, at: subject, against: clauses.dropFirst(), then: proceed)
    }
  }

  mutating func runWhile(
    _ c: Expression, _ body: Statement, then proceed: @escaping Next
  ) -> Onward {
    return evaluateAndConsume(c) { (runBody: Bool, me) in
      return runBody
        ? me.run(body) { me in me.runWhile(c, body, then: proceed)}
        : Onward(proceed)
    }
  }
}

/// Values and memory.
fileprivate extension Interpreter {
  /// Allocates an address earmarked for the eventual result of evaluating `e`,
  /// passing it on to `proceed` along with `self`.
  mutating func allocate(
    _ e: Expression, mutable: Bool = false, persist: Bool = false,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    let t = staticType[e]!
    let a = memory.allocate(boundTo: t, mutable: mutable)
    trace(
      e,
      "allocated \(a) bound to \(t) (\(persist ? "persistent" : "ephemeral"))")
    if persist {
      frame.persistentAllocations.push(a)
    }
    else {
      frame.ephemeralAllocations[a] = e
    }
    return a => proceed
  }

  /// Allocates an address for the result of evaluating `e`, passing it on to
  /// `proceed` along with `self`.
  mutating func allocate(
    _ e: Expression, unlessNonNil destination: Address?,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    destination.map { $0 => proceed } ?? allocate(e, then: proceed)
  }

  /// Destroys and reclaims memory of locally-allocated values at the top of the
  /// allocation stack until the stack's count is `n`.
  mutating func cleanUpPersistentAllocations(
    above n: Int, then proceed: @escaping Next) -> Onward
  {
    frame.persistentAllocations.count == n ? Onward(proceed)
      : deleteLocalValue_doNotCallDirectly(
        at: frame.persistentAllocations.pop()!
      ) { me in me.cleanUpPersistentAllocations(above: n, then: proceed) }
  }

  mutating func deleteLocalValue_doNotCallDirectly(
    at a: Address, then proceed: @escaping Next) -> Onward
  {
    if tracing { print("  info: deleting \(a)") }
    memory.deinitialize(a)
    memory.deallocate(a)
    return Onward(proceed)
  }

  /// If `a` was allocated to an ephemeral temporary, deinitializes and destroys
  /// it.
  mutating func deleteAnyEphemeral(
    at a: Address, then proceed: @escaping Next) -> Onward
  {
    if let _ = frame.ephemeralAllocations.removeValue(forKey: a) {
      return deleteLocalValue_doNotCallDirectly(at: a, then: proceed)
    }
    return Onward(proceed)
  }

  /// Deinitializes and destroys any addresses in `locations` that were
  /// allocated to an ephemeral temporary.
  mutating func deleteAnyEphemerals<C: Collection>(
    at locations: C, then proceed: @escaping Next) -> Onward
    where C.Element == Address
  {
    guard let a0 = locations.first else { return Onward(proceed) }
    return deleteAnyEphemeral(at: a0) { me in
      me.deleteAnyEphemerals(at: locations.dropFirst(), then: proceed)
    }
  }

  /// Copies the value at `source` into the `target` address and continues with
  /// `proceed`.
  mutating func copy(
    from source: Address, to target: Address,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    if tracing {
      print("  info: copying \(self[source]) into \(target)")
    }
    return initialize(target, to: self[source], then: proceed)
  }

  mutating func deinitialize(
    valueAt target: Address, then proceed: @escaping Next) -> Onward
  {
    if tracing {
      print("  info: deinitializing \(target)")
    }
    memory.deinitialize(target)
    return Onward(proceed)
  }

  mutating func initialize(
    _ target: Address, to v: Value,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    if tracing {
      print("  info: initializing \(target) = \(v)")
    }
    memory.initialize(target, to: v)
    return target => proceed
  }
}

/// Expression evaluation.
fileprivate extension Interpreter {
  /// Evaluates `e` into a value of type `T`, which is then passed to `proceed`.
  ///
  /// - Parameter asCallee: `true` if `e` is in callee position in a function
  ///   call expression.
  mutating func evaluateAndConsume<T>(
    _ e: Expression, asCallee: Bool = false,
    in proceed: @escaping Consumer<T>) -> Onward {
    evaluate(e) { p, me in
      let v = me[p] as! T
      return me.deleteAnyEphemeral(at: p) { me in proceed(v, &me) }
    }
  }

  /// Evaluates `e` (into `destination`, if supplied) and passes
  /// the address of the result on to `proceed_`.
  ///
  /// - Parameter asCallee: `true` if `e` is in callee position in a function
  ///   call expression.
  mutating func evaluate(
    _ e: Expression, asCallee: Bool = false, into destination: Address? = nil,
    then proceed_: @escaping Consumer<Address>) -> Onward
  {
    trace(
      e, "evaluating " + (asCallee ? "as callee " : "")
           + (destination != nil ? "into \(destination!)" : ""))

    let proceed = !tracing ? proceed_
      : { a, me in
        print("\(e.site): info: result = \(me[a])")
        return proceed_(a, &me)
      }

    // Handle all possible lvalue expressions
    switch e {
    case let .name(n):
      return evaluate(n, into: destination, then: proceed)

    case let .memberAccess(m):
      return evaluate(m, asCallee: asCallee, into: destination, then: proceed)

    case let .index(target: t, offset: i, _):
      return evaluateIndex(target: t, offset: i, into: destination, then: proceed)

    case .integerLiteral, .booleanLiteral, .tupleLiteral,
         .unaryOperator, .binaryOperator, .functionCall, .intType, .boolType,
         .typeType, .functionType:
      return allocate(e, unlessNonNil: destination) { result, me in
        switch e {
        case let .integerLiteral(r, _):
          return me.initialize(result, to: r, then: proceed)
        case let .booleanLiteral(r, _):
          return me.initialize(result, to: r, then: proceed)

        case let .tupleLiteral(t):
          return me.initialize(
            result,
            to: me.staticType[e]!.tuple!.mapFields {
              me.memory.uninitialized($0)
            })
          { _, me in
            me.evaluateTupleElements(
              t.fields().elements[...], into: result, then: proceed)
          }

        case let .unaryOperator(x):
          return me.evaluate(x, into: result, then: proceed)
        case let .binaryOperator(x):
          return me.evaluate(x, into: result, then: proceed)
        case let .functionCall(x):
          return me.evaluate(x, into: result, then: proceed)
        case .intType:
          return me.initialize(result, to: Type.int, then: proceed)
        case .boolType:
          return me.initialize(result, to: Type.bool, then: proceed)
        case .typeType:
          return me.initialize(result, to: Type.type, then: proceed)
        case let .functionType(f):
          // Create a partially initialized function type in memory, then
          // evaluate its parts into the corresponding memory locations.
          let parameterTypes = TupleLiteral(f.parameters)
          let parameterTypeTypes = me.staticType[.tupleLiteral(parameterTypes)]!

          let partialValue = Type.function(
            .init(
              parameterTypes: parameterTypeTypes
                .tuple!.mapFields { _ in Memory.uninitializedType },
              returnType: Memory.uninitializedType))

          return me.initialize(result, to: partialValue) { _, me in
            me.evaluateTupleElements(
              parameterTypes.fields().elements[...],
              into: result.addresseePart(
                \Type.function!.parameterTypes.upcastToValue, ".parameterTypes")
            ) { _, me in
              me.evaluate(
                f.returnType.body,
                into: result.addresseePart(
                  \Type.function!.returnType.upcastToValue, ".returnType")
              ) { _, me in result => proceed }
            }
          }

        case .name, .memberAccess, .index:
          UNREACHABLE()
        }
      }
    }
  }

  /// Evaluates `name` (into `destination`, if supplied) and passes the address
  /// of the result on to `proceed`.
  mutating func evaluate(
    _ name: Identifier, into destination: Address? = nil,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    let d = program.definition[name]

    switch d {
    case let t as TypeDeclaration:
      return allocate(.name(name), unlessNonNil: destination) { output, me in
        me.initialize(output, to: t.declaredType, then: proceed)
      }

    case let b as SimpleBinding:
      return addressOfInitialized(b) { source, me in
        destination != nil
          ? me.copy(from: source, to: destination!, then: proceed)
          : source => proceed
      }

    case let f as FunctionDefinition:
      let result = FunctionValue(
        dynamic_type:
          program.typeOfNameDeclaredBy[f.dynamicID]!.final!, code: f)

      return allocate(.name(name), unlessNonNil: destination) { output, me in
        me.initialize(output, to: result, then: proceed)
      }

    case let a as Alternative:
      UNIMPLEMENTED(a)

    case let m as StructMember:
      UNIMPLEMENTED(m)

    default:
      UNIMPLEMENTED(d as Any)
    }
  }

  mutating func addressOfInitialized(
    _ variable: SimpleBinding, then proceed: @escaping Consumer<Address>
  ) -> Onward {
    if let a = frame.locals[variable] ?? globals[variable] {
      return a => proceed
    }
    let i = program.enclosingInitialization[variable]!

    // Global variables will be bound to this memory, or parts of it, so it will
    // never be freed.
    let rhsArea = memory.allocate(
      boundTo: staticType[i.initializer]!, mutable: true)

    return evaluate(i.initializer, into: rhsArea) { rhs, me in
      me.match(
        i.bindings, toValueOfType: me.staticType[i.initializer]!, at: rhs
      ) { matched, me in
        if matched { return me.globals[variable]! => proceed }
        return me.error(
          i.bindings, "Initialization pattern not matched by \(me[rhs])")
      }
    }
  }

  /// Evaluates `e` into `output` and passes the address of the result on to
  /// `proceed`.
  mutating func evaluate(
    _ e: UnaryOperatorExpression, into output: Address,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    evaluate(e.operand) { operand, me in
      let result: Value
      switch e.operation.text {
      case "-": result = -(me[operand] as! Int)
      case "not": result = !(me[operand] as! Bool)
      default: UNREACHABLE()
      }
      return me.deleteAnyEphemeral(at: operand) { me in
        me.initialize(output, to: result, then: proceed)
      }
    }
  }

  /// Evaluates `e` into `output` and passes the address of the result on to
  /// `proceed`.
  mutating func evaluate(
    _ e: BinaryOperatorExpression, into output: Address,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    evaluate(e.lhs) { lhs, me in
      if e.operation.text == "and" && (me[lhs] as! Bool == false) {
        return me.copy(from: lhs, to: output, then: proceed)
      }
      else if e.operation.text == "or" && (me[lhs] as! Bool == true) {
        return me.copy(from: lhs, to: output, then: proceed)
      }

      return me.evaluate(e.rhs) { rhs, me in
        let result: Value
        switch e.operation.text {
        case "==": result = areEqual(me[lhs], me[rhs])
        case "-": result = (me[lhs] as! Int) - (me[rhs] as! Int)
        case "+": result = (me[lhs] as! Int) + (me[rhs] as! Int)
        case "and", "or": result = me[rhs] as! Bool
        default: UNIMPLEMENTED(e)
        }
        return me.deleteAnyEphemerals(at: [lhs, rhs]) { me in
          me.initialize(output, to: result, then: proceed)
        }
      }
    }
  }

  /// Evaluates `call` into `output` and passes the address of the result on to
  /// `proceed`.
  mutating func evaluate(
    _ call: FunctionCall<Expression>, into output: Address,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    switch staticType[call.callee]! {
    case .function:
      return evaluateCalledFunction(call, into: output, then: proceed)

    case .type:
      return evaluateStructLiteral(call, into: output, then: proceed)

    case .alternative:
      return evaluateChoiceLiteral(call, into: output, then: proceed)

    case .int, .bool, .choice, .struct, .tuple, .error:
      UNREACHABLE()
    }
  }

  /// Evaluates `call` into `output` and passes the address of the result on to
  /// `proceed`.
  ///
  /// - Requires: `call.callee` has function type.
  mutating func evaluateCalledFunction(
    _ call: FunctionCall<Expression>, into output: Address,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    evaluateAndConsume(call.callee, asCallee: true) {
      (callee: FunctionValue, me) in

      me.evaluate(.tupleLiteral(call.arguments)) { arguments, me in
        let savedFrame = me.frame

        // Set up the callee's frame.
        me.frame = CallFrame(
          resultAddress: output,
          onReturn: Onward { me in
            me.cleanUpPersistentAllocations(above: 0) { me in
              me.frame = savedFrame
              return me.deleteAnyEphemeral(at: arguments) { me in
                proceed(output, &me)
              }
            }
          })

        // Now we're in the context of the callee.
        let argumentsType = me.staticType[.tupleLiteral(call.arguments)]!

        return me.match(
          callee.code.parameters,
          toValueOfType: argumentsType.tuple!, at: arguments
        ) { matched, me in

          guard matched else {
            // refutable parameter lists not currently rejected in type checker.
            return me.error(
              call.arguments,
              "arguments don't match literal values in parameter list",
              notes: [("parameter list", callee.code.parameters.site)])
          }

          return me.run(callee.code.body!) { me in
            // Return an empty tuple when the function falls off the end.
            // We only arrive here if `onReturn` isn't invoked within the body.
            me.initialize(me.frame.resultAddress, to: Tuple()) {
              _, me in me.frame.onReturn
            }
          }
        }
      }
    }
  }

  /// Evaluates `call` into `output` and passes the address of the result on to
  /// `proceed`.
  ///
  /// - Requires: `call.callee` has alternative type.
  mutating func evaluateChoiceLiteral(
    _ call: FunctionCall<Expression>, into output: Address,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    guard case let .alternative(discriminator) = staticType[call.callee]
    else { UNREACHABLE() }

    let payloadType = program.alternativePayload[discriminator]!

    let partialResult = ChoiceValue(
      type: program.enclosingChoice[discriminator.structure]!.identity,
      discriminator: discriminator,
      payload: memory.uninitialized(.tuple(payloadType)))

    return initialize(output, to: partialResult) { _, me in
      let payloadAddress
        = output.addresseePart(\ChoiceValue.payload, ".payload")
      return me.evaluate(.tupleLiteral(call.arguments), into: payloadAddress)
      { _, me in output => proceed  }
    }
  }

  /// Evaluates `call` into `output` and passes the address of the result on to
  /// `proceed`.
  ///
  /// - Requires: `call.callee` is a `struct` type.
  mutating func evaluateStructLiteral(
    _ call: FunctionCall<Expression>, into output: Address,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    evaluateAndConsume(call.callee, asCallee: true) { (callee: Type, me) in
      guard case .struct(let structID) = callee else {
        UNREACHABLE()
      }
      let payloadType = me.staticType[.tupleLiteral(call.arguments)]!
      let partialResult = StructValue(
        type: structID, payload: me.memory.uninitialized(payloadType))

      return me.initialize(output, to: partialResult) { _, me in
        let payloadAddress
          = output.addresseePart(\StructValue.payload, ".payload")
        return me.evaluate(.tupleLiteral(call.arguments), into: payloadAddress)
        { _, me in output => proceed  }
      }
    }
  }

  /// Evaluates `e` (into `output`, if supplied) and passes the address of
  /// the result on to `proceed`.
  mutating func evaluate(
    _ e: MemberAccessExpression, asCallee: Bool, into output: Address?,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    evaluate(e.base) { base, me in
      switch me.staticType[e.base] {
      case .struct:
        let source = base.^e.member

        return output != nil
          ? me.copy(from: source, to: output!, then: proceed)
          : source => proceed
        
      case .tuple:
        let source = base.^e.member

        return output != nil
          ? me.copy(from: source, to: output!, then: proceed)
          : source => proceed

      case .type:
        // Handle access to a type member, like a static member in C++.
        switch Type(me[base])! {
        case let .choice(parentID):
          return me.allocate(.memberAccess(e), unlessNonNil: output)
          { output, me in

            let id: ASTIdentity<Alternative>
              = parentID.structure[e.member]!.identity
            let result: Value = asCallee
              ? AlternativeValue(id)
              : ChoiceValue(type: parentID, discriminator: id, payload: Tuple())

            return me.deleteAnyEphemeral(at: base) { me in
              me.initialize(output, to: result, then: proceed)
            }
          }
        default: UNREACHABLE()
        }
        fallthrough
      default:
        UNREACHABLE("\(e)")
      }
    }
  }

  mutating func evaluateIndex(
    target t: Expression, offset i: Expression, into output: Address?,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    evaluate(t, into: output) { targetAddress, me in
      me.evaluate(i) { indexAddress, me in
        let index = me[indexAddress] as! Int
        let resultAddress = targetAddress.^index

        return me.deleteAnyEphemeral(at: indexAddress) { me in
          output == nil ? proceed(resultAddress, &me)
            : me.copy(from: resultAddress, to: output!) { _, me in
              me.deleteAnyEphemeral(at: targetAddress) { me in
                proceed(output!, &me)
              }
            }
        }
      }
    }
  }

  /// Evaluates `e` into the elements of partially-formed tuple in `output`, and
  /// passes the address of the result on to `proceed`.
  mutating func evaluateTupleElements(
    _ e: Tuple<Expression>.Elements.SubSequence,
    into output: Address,
    positionalCount: Int = 0,
    then proceed: @escaping Consumer<Address>) -> Onward
  {
    if e.isEmpty { return proceed(output, &self) }
    let e0 = e.first!
    return evaluate(e0.value, into: output.^e0.key) { _, me in
      me.evaluateTupleElements(
        e.dropFirst(), into: output,
        positionalCount: positionalCount + (e0.key.position != nil ? 1 : 0),
        then: proceed)
    }
  }
}

func areEqual(_ l: Value, _ r: Value) -> Bool {
  switch (l as Any, r as Any) {

  case let (lh as AnyHashable, rh as AnyHashable):
    return lh == rh

  case let (lt as TupleValue, rt as TupleValue):
    return lt.count == rt.count && lt.elements.allSatisfy { k, v0 in
      rt.elements[k].map { v1 in areEqual(v0, v1) } ?? false
    }

  case let (lc as ChoiceValue, rc as ChoiceValue):
    return lc.discriminator == rc.discriminator
      && areEqual(lc.payload, rc.payload)

  case let (lt as TupleType, rt as TupleType):
    return lt == rt

  default:
    // All things that aren't equatable are considered equal if their types
    // match and unequal otherwise, to preserve reflexivity.
    return type(of: l) == type(of: r)
  }
}

/// Assignment
fileprivate extension Interpreter {
  /// Assigns the value at `source` into `t`, destructuring literal expressions
  /// of `t` and assigning into the lvalue subexpressions.
  mutating func assign(
    _ lhs: Expression, from source: Address,
    then proceed: @escaping Next) -> Onward
  {
    switch lhs {
    case .name, .index, .memberAccess:
      let preTargetEphemeralCount = frame.ephemeralAllocations
      return evaluate(lhs) { target, me in
        // If target is an lvalue, we should have been able to evaluate it
        // without new allocations.
        sanityCheck(
          me.frame.ephemeralAllocations == preTargetEphemeralCount,
          "\n\(lhs.site): error: not an lvalue?")
        me.memory.assign(from: source, into: target)
        return Onward(proceed)
      }

    case .integerLiteral, .booleanLiteral, .unaryOperator, .binaryOperator,
         .intType, .boolType, .typeType:
      UNREACHABLE("Non-lvalue expressions should be ruled out by TypeChecker.")

    case let .tupleLiteral(t):
      return assign(t, from: source, then: proceed)

    case let .functionCall(f):
      return assign(f, from: source, then: proceed)

    case let .functionType(t):
      return assign(t, from: source, then: proceed)
    }
  }

  mutating func assign(
    _ p: FunctionCall<Expression>, from source: Address,
    then proceed: @escaping Next) -> Onward
  {
    UNIMPLEMENTED()
  }

  mutating func assign(
    _ p: FunctionTypeLiteral, from source: Address,
    then proceed: @escaping Next) -> Onward
  {
    UNIMPLEMENTED()
  }

  mutating func assign(
    _ t: TupleLiteral, from source: Address,
    then proceed: @escaping Next) -> Onward
  {
    assignElements(t.fields().elements[...], from: source, then: proceed)
  }

  mutating func assignElements(
    _ t: Tuple<Expression>.Elements.SubSequence, from source: Address,
    then proceed: @escaping Next) -> Onward
  {
    guard let (k0, e0) = t.first else { return Onward(proceed) }

    return assign(e0, from: source.^k0) { me in
      me.assignElements(
        t.dropFirst(), from: source, then: proceed)
    }
  }
}

/// Pattern matching
fileprivate extension Interpreter {
  /// Matches `p` to the value at `source`, binding variables in `p` to
  /// the corresponding parts of the value, and calling `proceed` with an
  /// indication of whether the match was successful.
  mutating func match(
    _ p: Pattern,
    toValueOfType sourceType: Type, at source: Address,
    then proceed: @escaping Consumer<Bool>) -> Onward
  {
    trace(p, "matching against value \(self[source])")
    switch p {
    case let .atom(t):
      return evaluate(t) { target, me in
        let matched = areEqual(me[target], me[source])
        return me.deleteAnyEphemeral(at: target) { me in
          proceed(matched, &me)
        }
      }

    case let .variable(b):
      trace(b.name, "binding \(self[source]) \(source)")
      if program.globals.contains(b.identity) { globals[b] = source }
      else { frame.locals[b] = source }
      return true => proceed

    case let .tuple(x):
      return match(
        x, toValueOfType: sourceType.tuple!, at: source, then: proceed)

    case let .functionCall(x):
      return match(x, toValueOfType: sourceType, at: source, then: proceed)

    case let .functionType(x): UNIMPLEMENTED(x)
    }
  }

  mutating func match(
    _ p: FunctionCall<Pattern>,
    toValueOfType subjectType: Type, at subject: Address,
    then proceed: @escaping Consumer<Bool>) -> Onward
  {
    switch subjectType {
    case .struct:
      UNIMPLEMENTED()

    case .choice:
      let subjectAlternative = (self[subject] as! ChoiceValue).discriminator

      if staticType[p.callee] != .alternative(subjectAlternative) {
        return false => proceed
      }

      return match(
        p.arguments,
        toValueOfType: program.alternativePayload[subjectAlternative]!,
        at: subject, then: proceed)

    case .int, .bool, .type, .function, .tuple, .error, .alternative:
      UNREACHABLE()
    }
  }

  mutating func match(
    _ p: TuplePattern,
    toValueOfType subjectTypes: Tuple<Type>, at subject: Address,
    then proceed: @escaping Consumer<Bool>) -> Onward
  {
    let p1 = p.fields()
    if !subjectTypes.isCongruent(to: p1) { return false => proceed }

    return matchElements(
      p1.elements[...],
      toValuesOfType: subjectTypes, at: subject, then: proceed)
  }

  mutating func matchElements(
    _ p: Tuple<Pattern>.Elements.SubSequence,
    toValuesOfType subjectTypes: Tuple<Type>, at subject: Address,
    then proceed: @escaping Consumer<Bool>) -> Onward
  {
    guard let (k0, p0) = p.first else { return true => proceed }
    return match(
      p0, toValueOfType: subjectTypes[k0]!, at: subject.^k0
    ) { matched, me in
      if !matched { return false => proceed }
      return me.matchElements(
        p.dropFirst(),
        toValuesOfType: subjectTypes, at: subject, then: proceed)
    }
  }
}

// TODO: move this
/// Just like the built-in assert except that it prints the full path to the
/// file.
///
/// Better for IDEs.
func sanityCheck(
  _ condition: @autoclosure () -> Bool,
  _ message: @autoclosure () -> String = String(),
  filePath: StaticString = #filePath, line: UInt = #line
) {
  Swift.assert(condition(), message(), file: (filePath), line: line)
}

/// Facility for the interpreter, not to be touched by other parts of the system.
fileprivate extension TupleSyntax {
  /// Creates a `Tuple` from `self`, requiring there be no duplicate fieldIDs.
  ///
  /// Duplicate fieldIDs should already have been rejected by the typechecker.
  func fields() -> Tuple<Payload> {
    var l = ErrorLog()
    let r = fields(reportingDuplicatesIn: &l)
    sanityCheck(l.isEmpty)
    return r
  }
}
// TODO: break assign down into subtasks.
// TODO: output vs. destination?
