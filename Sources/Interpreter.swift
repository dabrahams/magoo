// Part of the Carbon Language project, under the Apache License v2.0 with LLVM
// Exceptions. See /LICENSE for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

/// The engine that executes the program
struct Interpreter {
  /// Creates an instance for executing `program`.
  init(_ program: ExecutableProgram) {
    self.program = program
  }

  /// The program being executed.
  var //let
    program: ExecutableProgram

  /// A type that can represent the local variables and expression values.
  ///
  /// The expression values include temporaries, but also references to lvalues.
  // Temporarily using SourceRegion rather than AST node identity to work
  // around some weaknesses in the grammar.
  typealias Locals = [SourceRegion: Address]

  /// A mapping from ID of expressions and declarations to local addresses.
  var locals: Locals = [:]

  /// The address that should be filled in by any `return` statements.
  var returnValueStorage: Address = -1

  /// A type that captures everything that needs to be restored after a callee
  /// returns.
  typealias FunctionContext = (locals: Locals, returnValueStorage: Address)

  /// The function execution context.
  var functionContext: FunctionContext {
    get { (locals, returnValueStorage) }
    set { (locals, returnValueStorage) = newValue }
  }

  typealias ExitCode = Int

  /// Mapping from global declaration to addresses.
  // private(set)
    var globals: [Declaration.Identity: Address] = [:]

  var memory = Memory()

  private(set) var termination: ExitCode? = nil

  /// The stack of pending actions.
  private var todo = Stack<Action>()
}

extension Interpreter {
  /// Progress one step forward in the execution sequence, returning an exit
  /// code if the program terminated.
  mutating func step() {
    guard var current = todo.pop() else {
      termination = 0
      return
    }
    switch current.run(on: &self) {
    case .done: return
    case .spawn(let child):
      todo.push(current)
      todo.push(child)
    case .chain(to: let successor):
      todo.push(successor)
    }
  }

  /// Accesses or initializes an rvalue for the given expression.
  ///
  /// - Requires: `e` comes from the current function context.
  subscript(_ e: Expression) -> Value {
    get {
      return memory[address(of: e)]
    }
    set {
      precondition(
        locals[e.site] == nil, "Temporary already initialized.")
      let a = memory.allocate(
        boundTo: newValue.type, from: e.site, mutable: false)
      memory.initialize(a, to: newValue)
      locals[e.site] = a
    }
  }

  /// Destroys any rvalue computed for `e` and removes `e` from `locals`.
  mutating func cleanUp(_ e: Expression) {
    defer { locals[e.site] = nil }
    if case .variable(_) = e^ { return } // not an rvalue.

    let a = locals[e.site]!
    memory.deinitialize(a)
    memory.deallocate(a)
  }

  /// Accesses the value stored for the declaration of the given name.
  subscript(_ name: Identifier) -> Value {
    return memory[address(of: name)]
  }

  /// Accesses the address of the declaration for the given name.
  func address(of name: Identifier) -> Address {
    let d = program.declaration[name]
    return locals[d.site] ?? globals[d.identity!]!
  }

  /// Accesses the address where e's value is stored.
  func address(of e: Expression) -> Address {
    return locals[e.site]!
  }
}

struct FunctionValue: Value {
  let type: Type
  let code: FunctionDefinition
}

extension Interpreter {
  mutating func pushTodo_testingOnly(_ a: Action) { todo.push(a) }
}
