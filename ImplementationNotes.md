# Implementation Notes

- If you have to look at the scanner details, you'll see a lot of translation
  between UTF-16 offsets and String indices.  This is because Foundation's
  regular expression support still(!) hasn't caught up with modern Swift.  It's
  ugly but if you have to do something with regular expressions, reading this
  code will show you how.

## Things that should definitely be fixed at some point (IMO).

- There's a somewhat complicated system for translating the locations of errors
  that come out of examples in string literals like those found in
  TestTypeChecker.swift, so they point into the source (comment out the `+`
  operators in `SourceRegion` and the compiler will point you at it).
  Unfortunately, trace messages aren't errors and therefore don't get translated
  in the same way.  It would be much better/simpler to adjust the string before
  it is parsed, with a bunch of newlines and indentation on each line to make
  locations in the string line up with locations in the test file,
  e.g. (untested code):

      ```swift
      let adjustedText = String(repeating: "\n", count: lineOffset)
        + text.split(separator: "\n").map {
            String(repeating: " ", count: indent) + $0
          }
          .joined(separator: "\n")
      ```
- Errors thrown out of the parser should be converted to `CarbonError` so that
  we get good diagnostics for failed parses, like we do for failed
  type-checking.
  
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

- Currently the testdata example files are tested in several different test
  files, to exercise the different phases, but in fact the interpreter tests
  exercise everything.  Especially once the system in the bullet above is set
  up, this duplication could be eliminated.

## Things you might want to consider changing.

Obviously you can make any change that makes sense to you, but there are a few
things I'd like to suggest you consider.

- Swift `Keypaths` as used in `Address` are a bit opaque, and—especially for
  debugging—might be better replaced by an array of some enum type
  (`Int`+`String`+x0+x1…) where the x's are special cases created to describe
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

- Naming.  I follow a general principle of avoiding the use of type information
  in non-type names, having found that the space is almost always better used to
  express something about the *role* of the entity.  However, I haven't written
  much code in a domain where there are often so many views of a thing with the
  same role: e.g., the target of an assignment has a value, a type, an
  expression, and an address, and you might need to use all of them together in
  the interpreter.  It's often a struggle to figure out which one should be
  primary (i.e. called “`target`”), and to choose weildy names for the others.
  It might be better in this case to adopt a terse convention for these things
  project-wide, e.g. `targetV`, `targetT`, `targetE`, `targetA`.  I normally
  don't do abbrevs but in this case I think spelling out the same words over and
  over might do more harm than good.

- Consider standardizing the single-unlabeled-payload-element pattern for `enum`
  cases, which makes it cleaner to factor large `switch` statements into separate
  functions.  Right now some enum case payloads have multiple elements.

- The trace output could be more useful/standardized.  The source location stuff
  that highlights code as you step through the trace is great, but I'm not
  convinced the other aspects are optimal.
