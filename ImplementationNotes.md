# Implementation Notes

This file documents implementation details, especially those with known
weaknesses.  It is expected that the right design reveals itself as the work
goes on.

## General notes

- If you have to look at the scanner details, you'll see a lot of nasty
  translation between UTF-16 offsets and String indices.  This is because
  Foundation's regular expression support still(!) hasn't caught up with modern
  Swift.  It's ugly but if you have to do something with regular expressions,
  reading this code will show you how.

- Various compromises were made to cut down on boilerplate for the reader of the
  code.  For example, normally I'd mark a type's API as `public` (even if the
  type was `private` to some other scope).  Instead, I've left most APIs
  `internal`, relying on an `@testable import` to expose them to test files.

- `Value` is an existential protocol rather than an `enum` primarily so there
  can be an is-a relationship between `Type` and `Value`.  There's no reason
  `Type` couldn't also be a protocol, but one loses the maintainability
  advantage of switch coverage testing.  Trade-offs.

- Using code coverage data (see README.md) and systematically eliminating
  `UNIMPLEMENTED`s was an incredibly useful way to produce complete tests for
  the type checker. Highly recommended for other parts of the system!
  
## Things that should definitely be fixed at some point (IMO).

- Unless you start requiring braces around the bodies of `if`/`else` and `while`
  statements, they should be interpreted inside an `inScope` call.  Currently,
  the lifetime of the rhs of any intialization statement that forms the entire
  body of such a statement, without enclosing braces, will extend till the end
  of the enclosing block.

- There's a somewhat complicated system for translating the locations of errors
  that come out of examples in string literals like those found in
  TestTypeChecker.swift, so they point into the source (comment out the `+`
  operators in `SourceRegion` and the compiler will point you at the code for
  this system).  Unfortunately, trace messages aren't errors and therefore don't
  get translated in the same way.  It would be much better/simpler to adjust the
  string before it is parsed, with a bunch of newlines and indentation on each
  line to make locations in the string line up with locations in the test file,
  e.g. (untested code):

      ```swift
      let adjustedText = String(repeating: "\n", count: lineOffset)
        + text.split(separator: "\n").map { indentation(indent) + $0 }
          .joined(separator: "\n")
      ```
- Errors thrown out of the parser should be converted to `CarbonError` so that
  we get good diagnostics for failed parses, like we do for failed
  type-checking.  Citron supports a more sophisticated system, so parsing can
  produce even more informative diagnostics, and recover, but it's unclear to me
  that using it would be a worthwhile investment for executable semantics.
  
- An system somewhat like LLVM's `lit` tool that lets you embed information
  about expected errors and return codes in Carbon comments, for the purposes of
  testing, should be set up.  The `.golden` files that are used for this purpose
  in the C++ implementation made sense when we were looking at the entire trace
  output of the program, but we don't really want to test for stability of the
  trace, at least at this point in the project, and now many of them just say
  what the program's return code is.  Separating this info from the source
  creates a burden on the developer that isn't balanced by any benefits, because
  they can't pick up an example file and easily see what's supposed to happen
  and where.  You can see in some of the tests I am approximating this system
  looking for the string `"Error expected."`, and crudely expecting them to fail
  typechecking, but it would be better to tag the line that's expected to fail
  and provide an expected message excerpt and check that it's on the right line;
  likewise it might be good to explicitly distinguish which phase is expected to
  fail. Sometimes it's not obvious from a message whether it's a compile-time or
  runtime failure. See the scanner code for swift regex examples.

- Currently the testdata example files are tested in several different Swift
  test files, to exercise the different phases, but in fact the interpreter
  tests exercise everything.  Especially once the system in the bullet above is
  set up, this duplication could be eliminated.

- Some effort was made to distinguish the grammar for patterns that bind at
  least one variable (see the `binding` symbol) from those that are just
  expressions.  This distinction ensures that the parser disallows
  initializations like `var 3 = 3`, that don't bind any variables, but it adds a
  lot of grammar complexity, and is probably better/simpler to handle in the
  typechecker (and may fall out of statically ensuring irrefutability).
  
## Things you might want to consider changing.

Obviously you can make any change that makes sense to you, but there are a few
things I'd like to suggest you consider.

- Swift `Keypaths` as used in `Address` are a bit opaque, and???especially for
  debugging???might be better replaced by an array of some enum type
  (`Int`+`String`+x0+x1???) where the x's are special cases created to describe
  non-value things like the fields of `FunctionType`.  Then you could stop
  storing an explicit `description` and synthesize it from the array.
  
- There are lots of subscript operations that use the Swift `Dictionary`
  standard of returning an optional that says whether the lookup key was found,
  but in 99% of lookups we know the key is there.  Consequently, you see a lot
  of force-unwraps (`!`) in the code.  It might be better to use the Swift
  `Array` standard, which is to make it a precondition that the element exists.
  If you decide to do that, [this
  file](https://github.com/dabrahams/carbon-lang/blob/known-dictionary/Sources/KnownDictionary.swift)
  might be a useful start (the first doc comment needs to be corrected; it's
  just like Swift's `Dictionary` but with this different convention and an
  `insert` function to insert a new key).  Even simpler might be just to wrap
  the read-only lookups in a function/method call.

- Naming: I follow a general principle of avoiding the use of type information
  in non-type names, having found that the space is almost always better used to
  express something about the *role* of the entity.  However, I haven't written
  much code in a domain where there are often so many views of a thing with the
  same role: e.g., the target of an assignment has a value, a type, an
  expression, and an address, and you might need to use all of them together in
  the interpreter.  It's often a struggle to figure out which one should be
  primary (i.e. called ???`target`???), and to choose weildy names for the others.
  It might be better in this case to adopt a terse convention for these things
  project-wide, e.g. `targetV`, `targetT`, `targetE`, `targetA`.  I normally
  don't do abbrevs but in this case I think spelling out the same words over and
  over might do more harm than good.
  
- Naming: more consistency could be established; the interpreter uses both
  ???output??? and ???destination??? (and probably ???result??? too) to mean the address of
  a computed result.

- Consider standardizing the single-unlabeled-payload-element pattern for `enum`
  cases, which makes it cleaner to factor large `switch` statements into separate
  functions.  Right now some enum case payloads have multiple elements.

- The trace output could be more useful/standardized.  The source location stuff
  that highlights code as you step through the trace is great, but I'm not
  convinced the other aspects are optimal.  In particular, the interpreter
  tracing is not doing indentation to denote nesting level the way the
  typechecker tracing does, and the latter could be more consistent.

- The `Declaration` protocol and its refinement, `TypeDeclaration`, used as
  existentials, are not necessarily pulling their weight and create a
  discontinuity with the ???closed??? polymorphism created created by the `enum`s
  used elsewhere.  It might be better to eliminate them or replace them with
  `enums`.

- `Int` and `Bool` have been extended to conform to `Value`, which gives them a
  `subscript` operator.  If you find that jarring, consider creating `IntValue`
  and `BoolValue` `struct`s.

- Column limit: I used 80 columns so that readers wouldn't think I was giving
  Swift an unfair advantage over Carbon's C++ code, but the standard enforced by
  Google's swift-format tool is 100, and there are quite a few places where the
  extra 20 columns would improve readability.
  
- Omitting `public`: it may get confusing when you see `private(set) var x: Y`
  which really means `internal private(set) var x: Y`, i.e. a property that's
  publicly readable and privately writable.  Consider marking these things
  explicitly `public` inside of (implicitly) `internal` types.  Be warned that
  about exposing module-level declarations as `public` can sometimes sign you up
  for more than you bargained for, as types *used in* those declarations need to
  be `public` too (unlike in C++, type aliases are not immune).
  
- ???Definition??? and ???declaration??? are used somewhat interchangeably in names
  throughout the code.  Someone should figure out what these terms really mean
  to Carbon and decide how they should be used in the source.

- There is significant code duplication between pattern and expression type
  computation.  On the one hand, I know for a fact that handling each one
  independently has prevented bugs.  On the other, somebody could think about
  factoring out the commonality.

- Code organization is somewhat freeform, with helper utilities like
  `UNIMPLEMENTED` and `UNREACHABLE` defined in the file where they were first
  needed.
  
- The use of ad-hoc overloading was very convenient for initial implementation
  (saved me from having to come up with new names), but I'm not convinced it's a
  win for overall comprehensibility and maintainability. When ???search for this
  name??? gives you multiple choices it's less useful than when it gives you just
  one.

- More complete interpreter testing using code coverage and eliminating uses of
  `UNIMPLEMENTED()`.  Lots of tiny examples, as in TestTypeChecker.swift.
  
- If you don't want to worry about formatting, integrate swift-format as the
  main project has integrated clang-tidy.
  
- `UNREACHABLE` should have a signature like `UNIMPLEMENTED`, taking variadic
  arguments rather than a string.  Can always pass a string.
  
- It might be better to have distinct enums for the set of unary and binary
  operators, rather than reusing TokenIDs.  Then you could get complete matching
  checks for handlers of these operators and maybe `Token` wouldn't need to
  conform to `AST`.
  
- I have an inkling that the pattern matching code would shrink if we were
  primarily switching on the `staticType` of the subject-to-be-matched rather
  than on the syntactic form of the pattern.

