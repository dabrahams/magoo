// Part of the Carbon Language project, under the Apache License v2.0 with LLVM
// Exceptions. See /LICENSE for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

/// A program whose semantic analysis/compilation is complete, containing all
/// the information necessary for execution.
struct ExecutableProgram {
  /// The result of running the parser
  let ast: AbstractSyntaxTree

  /// A mapping from identifier to its definition.
  let definition: ASTDictionary<Identifier, Declaration>

  /// The variables defined at global scope.
  let globals: Set<ASTIdentity<SimpleBinding>>

  /// Mapping from expression to the static type of that expression.
  let staticType: ASTDictionary<Expression, Type>

  /// The payload tuple type for each alternative.
  let alternativePayload: [ASTIdentity<Alternative>: TupleType]
  // Note: ASTDictionary would not be a win here.

  /// Mapping from alternative declaration to the choice in which it is defined.
  let enclosingChoice: ASTDictionary<Alternative, ChoiceDefinition>

  /// Mapping from variable declaration to the initialization in which it is
  /// defined.
  let enclosingInitialization: ASTDictionary<SimpleBinding, Initialization>

  /// The type of the expression consisting of the name of each declared entity.
  let typeOfNameDeclaredBy: Dictionary<AnyASTIdentity, Memo<Type>>

  /// The unique top-level nullary main() function defined in `ast`,
  /// or `nil` if that doesn't exist.
  var main: FunctionDefinition? {
    // The nullary main functions defined at global scope
    let candidates = ast.compactMap { (x)->FunctionDefinition? in
      if case .function(let f) = x, f.name.text == "main", f.parameters.isEmpty
      { return f } else { return nil }
    }
    if candidates.isEmpty { return nil }

    assert(
      candidates.count == 1,
      "Duplicate definitions should have been ruled out by name resolution.")
    return candidates[0]
  }

  /// Creates an instance for the given parser output, or throws `ErrorLog` if
  /// the program is ill-formed.
  init(_ parsedProgram: AbstractSyntaxTree) throws {
    let nameLookup = NameResolution(parsedProgram)
    if !nameLookup.errors.isEmpty { throw nameLookup.errors }
    let typeChecking = TypeChecker(parsedProgram, nameLookup: nameLookup)
    if !typeChecking.errors.isEmpty { throw typeChecking.errors }
    self.init(parsedProgram, nameLookup: nameLookup, typeChecking: typeChecking)
  }

  /// Creates an instance for expression evaluation during typechecking.
  init(
    _ parsedProgram: AbstractSyntaxTree,
    nameLookup: NameResolution, typeChecking: TypeChecker
  ) {
    self.ast = parsedProgram
    self.definition = nameLookup.definition
    self.globals = nameLookup.globals
    self.staticType = typeChecking.expressionType
    self.alternativePayload = typeChecking.alternativePayload
    self.enclosingChoice = typeChecking.enclosingChoice
    self.enclosingInitialization = typeChecking.enclosingInitialization
    self.typeOfNameDeclaredBy = typeChecking.typeOfNameDeclaredBy
  }
}
