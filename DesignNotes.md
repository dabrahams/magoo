# Design Notes

## Architecture

The system is primarily built in phases that (with one exception) are simple
sequential dependencies:

1. Lexical analysis (Scanner.swift, Token.swift, SourceRegion.swift)
2. Parsing (Parser.citron, AST.swift)
3. Name resolution (Name Resolution.swift)
4. Type checking (TypeChecker.swift, Type.swift, Value.swift)
5. Interpretation (Interpreter.swift, Memory.swift)

The one exception to the phase ordering is that the type checker uses the
interpreter to evaluate compile-time expressions, including types.  This
dependency inversion can be disabled, with a corresponding diminishment of
language capability, by compiling with `-DNO_COMPILE_TIME_COMPUTE` (or by
editing the source where `NO_COMPILE_TIME_COMPUTE` appears in
TypeChecker.swift).

### Lexical Analysis

The scanner is not production-performance because it uses regular expressions,
but “should” otherwise be totally solid. It should eventually be [contributed
back](https://github.com/roop/citron/issues/12) to the
[Citron](http://roopc.net/citron/) project that supplies the parser generator,
but whose lexer does not obey the max-munch rule (and performs even worse).  The
top part of Scanner.swift contains the high-level specification of token
patterns, and is all anybody should have to edit in order to change the tokens
of the Carbon language.

The scanner counts characters (Unicode grapheme clusters) and newlines to track
the start and end position of each token recognized. That range, along with a
filename, is captured in a `SourceRegion`, which is used for diagnostics, and to
uniquely identify AST nodes (see the Parsing section).

### The AST 

The AST (AST.swift) is the central data structure for that everything after
lexical analysis operates on, so is key for understanding the rest of the system.

#### Node Equality and Identity

The AST representation uses Swift enums and `struct`s, which are all value
types, like `Int` or `std::vector` in C++ (but with lazy COW for deep data).  In
safe Swift, a value doesn't have an identity; you can only differentiate two
values based on their contents. Since, e.g. `var x: auto` can appear multiple
times in a program, each one meaning something different, we need some way to
tell the difference between two AST nodes with identical contents.

The current approach is to use the `SourceRegion` plus the node type as a unique
identifier.  If node types correspond to grammar symbols, two distinct nodes
having the same type and source region is impossible—it would imply the parser
is in an infinite loop.  So node identity is based on location.

Node *equality*, though, is based on content/structure, not location.  That
allows us to check whether two `Identifier`s have the same name with simple
equality and use them as hash keys, and to test that the parser gives expected
results.

To allow Swift to synthesize `Equatable` conformance for AST nodes, 

### Parsing


We use the [Citron](http://roopc.net/citron/) parser generator, which is derived
from the widely-ported [Lemon](https://www.hwaci.com/sw/lemon/lemon.html).
