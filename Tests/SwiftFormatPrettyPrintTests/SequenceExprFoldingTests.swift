import SwiftFormatPrettyPrint
import SwiftSyntax
import SwiftParser
import XCTest

final class SequenceExprFoldingTests: XCTestCase {
  private var context: OperatorContext!

  override func setUp() {
    context = .makeBuiltinOperatorContext()
  }

  func testSimpleBinaryExprIsUnchanged() {
    assertFoldedExprStructure("a + b", "{ a + b }")
    assertFoldedExprStructure("a * b", "{ a * b }")
    assertFoldedExprStructure("a -> b", "{ a -> b }")
    assertFoldedExprStructure("a = b", "{ a = b }")
  }

  func testSimpleBinaryExprLeftAssociativity() {
    assertFoldedExprStructure("a + b + c", "{{ a + b } + c }")
    assertFoldedExprStructure("a + b + c + d", "{{{ a + b } + c } + d }")
  }

  func testSimpleBinaryExprRightAssociativity() {
    assertFoldedExprStructure("a -> b -> c", "{ a -> { b -> c }}")
    assertFoldedExprStructure("a -> b -> c -> d", "{ a -> { b -> { c -> d }}}")
  }

  func testDifferentOperatorsSamePrecedence() {
    assertFoldedExprStructure("a * b / c", "{{ a * b } / c }")
  }

  func testBinaryMixedPrecedence() {
    assertFoldedExprStructure("a || b && c + d", "{ a || { b && { c + d }}}")
    assertFoldedExprStructure("a && b || c + d", "{{ a && b } || { c + d }}")
    assertFoldedExprStructure("a + b && c || d", "{{{ a + b } && c } || d }")
    assertFoldedExprStructure("a || b + c && d", "{ a || {{ b + c } && d }}")
    assertFoldedExprStructure("a || b && c + d", "{ a || { b && { c + d }}}")
    assertFoldedExprStructure("a + b || c && d", "{{ a + b } || { c && d }}")
  }

  func testAssignment() {
    assertFoldedExprStructure("a = b", "{ a = b }")
    assertFoldedExprStructure("a = b + c", "{ a = { b + c }}")
  }

  func testMixedAssociativity() {
    assertFoldedExprStructure(
      "a + b + c ?? d ?? e",
      "{{{ a + b } + c } ?? { d ?? e }}")
    assertFoldedExprStructure(
      "a + b + c ?? d ?? e -> f",
      "{{{{ a + b } + c } ?? { d ?? e }} -> f }")
  }

  func testSimpleTernary() {
    assertFoldedExprStructure("a ? b : c", "{ a ? b : c }")
  }

  func testComplexTernary() {
    assertFoldedExprStructure("a + b ? c : d", "{{ a + b } ? c : d }")
    assertFoldedExprStructure("a = b ? c : d", "{ a = { b ? c : d }}")
    assertFoldedExprStructure(
      "a && b ? c + d : e * f",
      "{{ a && b } ? { c + d } : { e * f }}")
  }

  func testNestedTernary() {
    assertFoldedExprStructure(
      "a ? b : c ? d : e",
      "{ a ? b : { c ? d : e }}")
    assertFoldedExprStructure(
      "a ? b ? c : d : e",
      "{ a ? { b ? c : d } : e }")
    assertFoldedExprStructure(
      "a ? b : c ? d : e ? f : g",
      "{ a ? b : { c ? d : { e ? f : g }}}")
    assertFoldedExprStructure(
      "a ? b ? c ? d : e : f : g",
      "{ a ? { b ? { c ? d : e } : f } : g }")
  }

  func testSimpleCastExpressions() throws {
    throw XCTSkip("Expression folding does not account for updated sequence expression structure.")

    assertFoldedExprStructure("a as B", "{ a as B }")
    assertFoldedExprStructure("a is B", "{ a is B }")

    assertFoldedExprStructure("a = b as C", "{ a = { b as C }}")
    assertFoldedExprStructure("a = b as C + d", "{ a = {{ b as C } + d }}")
    assertFoldedExprStructure("a = b as C ?? d", "{ a = {{ b as C } ?? d }}")
  }

  func testComplexCastExpressions() throws {
    throw XCTSkip("Expression folding does not account for updated sequence expression structure.")

    assertFoldedExprStructure("a + b as C", "{{ a + b } as C }")
    assertFoldedExprStructure("a < b as C", "{ a < { b as C }}")
    assertFoldedExprStructure(
      "a is X && b is Y && c is Z",
      "{{{ a is X } && { b is Y }} && { c is Z }}")
  }

  func testTryFolding() {
    assertFoldedExprStructure("try a() + b", "try { a ( ) + b }")
    assertFoldedExprStructure("try a() + b * c", "try { a ( ) + { b * c }}")
  }

  func testTryTernaryFolding() {
    assertFoldedExprStructure(
      "a ? b : try c() + d",
      "{ a ? b : try { c ( ) + d }}")
    assertFoldedExprStructure(
      "a ? b : try c() + d * e",
      "{ a ? b : try { c ( ) + { d * e }}}")
  }

  func testAwaitFolding() {
    assertFoldedExprStructure("await a() + b", "await { a ( ) + b }")
    assertFoldedExprStructure("await a() + b * c", "await { a ( ) + { b * c }}")
  }

  func testAwaitTernaryFolding() {
    assertFoldedExprStructure(
      "a ? b : await c() + d",
      "{ a ? b : await { c ( ) + d }}")
    assertFoldedExprStructure(
      "a ? b : await c() + d * e",
      "{ a ? b : await { c ( ) + { d * e }}}")
  }

  func testTryAwaitFolding() {
    assertFoldedExprStructure("try await a() + b", "try await { a ( ) + b }")
    assertFoldedExprStructure("try await a() + b * c", "try await { a ( ) + { b * c }}")
  }

  func testTryAwaitTernaryFolding() {
    assertFoldedExprStructure(
      "a ? b : try await c() + d",
      "{ a ? b : try await { c ( ) + d }}")
    assertFoldedExprStructure(
      "a ? b : try await c() + d * e",
      "{ a ? b : try await { c ( ) + { d * e }}}")
  }

  func testUnrecognizedOperators() {
    // If we see an operator we don't recognize, we arbitrarily bind them with
    // left associativity. This occurs even if something with high precedence,
    // like `<<`, follows it later in the sequence.
    assertFoldedExprStructure("a << b *!* c", "{{ a << b } *!* c }")
    assertFoldedExprStructure("a *!* b << c", "{{ a *!* b } << c }")
    assertFoldedExprStructure("a -> b *!* c", "{{ a -> b } *!* c }")
    assertFoldedExprStructure("a *!* b -> c", "{{ a *!* b } -> c }")
    assertFoldedExprStructure("a *!* b *&* c", "{{ a *!* b } *&* c }")
  }

  func testCustomOperator() {
    // "Lower than bitwise shift" probably isn't what we would actually use if
    // we were actually defining this, but it gives us coverage of that code
    // path since the builtin operators don't.
    let exponentPrecedence = PrecedenceGroup(
      lowerGroups: [context.precedenceGroup(named: .bitwiseShift)!],
      higherGroups: [context.precedenceGroup(named: .multiplication)!],
      associativity: .right)
    context.addPrecedenceGroup(
      exponentPrecedence, named: PrecedenceGroup.Name("ExponentPrecedence"))
    context.addInfixOperator("**", precedenceGroup: exponentPrecedence)

    assertFoldedExprStructure("a * b ** c + d", "{{ a * { b ** c }} + d }")
    assertFoldedExprStructure("a ** b * c + d", "{{{ a ** b } * c } + d }")
    assertFoldedExprStructure("a ** b ** c + d", "{{ a ** { b ** c }} + d }")
    assertFoldedExprStructure("a * b ** c + d", "{{ a * { b ** c }} + d }")
    assertFoldedExprStructure("a * b + c ** d", "{{ a * b } + { c ** d }}")
  }

  func testMixedCastsTriesAndTernaries() throws {
    throw XCTSkip("Expression folding does not account for updated sequence expression structure.")

    // These are some regression tests around some mixed cast, try, and ternary
    // expressions that the folding algorithm originally didn't handle correctly
    // because it either didn't detect that it needed to fold them at all or it
    // did not recursively duplicate the cast expression when it was inside a
    // ternary condition or false choice (causing the odd-length precondition to
    // fail).
    assertFoldedExprStructure(
      "b is C ? d : e",
      "{{ b is C } ? d : e }")
    assertFoldedExprStructure(
      "b is X ? c : d as Z",
      "{{ b is X } ? c : { d as Z }}")
    assertFoldedExprStructure(
      "b is X ? c as Y : d",
      "{{ b is X } ? { c as Y } : d }")
    assertFoldedExprStructure(
      "b is X ? c as Y : d as Z",
      "{{ b is X } ? { c as Y } : { d as Z }}")

    assertFoldedExprStructure(
      "a = b is C ? d : e",
      "{ a = {{ b is C } ? d : e }}")
    assertFoldedExprStructure(
      "a = b is X ? c : d as Z",
      "{ a = {{ b is X } ? c : { d as Z }}}")
    assertFoldedExprStructure(
      "a = b is X ? c as Y : d",
      "{ a = {{ b is X } ? { c as Y } : d }}")
    assertFoldedExprStructure(
      "a = b is X ? c as Y : d as Z",
      "{ a = {{ b is X } ? { c as Y } : { d as Z }}}")

    assertFoldedExprStructure(
      "a ? b : c as Z",
      "{ a ? b : { c as Z }}")
    assertFoldedExprStructure(
      "a ? b as Y : c as Z",
      "{ a ? { b as Y } : { c as Z }}")
    assertFoldedExprStructure(
      "a as X ? b : c as Z",
      "{{ a as X } ? b : { c as Z }}")
    assertFoldedExprStructure(
      "a as X ? b as Y : c as Z",
      "{{ a as X } ? { b as Y } : { c as Z }}")

    assertFoldedExprStructure(
      "a ? try b : try c as Z",
      "{ a ? try b : try { c as Z }}")
    assertFoldedExprStructure(
      "a as X ? try b : try c as Z",
      "{{ a as X } ? try b : try { c as Z }}")
  }

  /// Asserts that a sequence expression, after folding, as the expected
  /// structure.
  ///
  /// See the `SequenceExprStructureWriter` type below for a description of the
  /// string representation of the folded expression.
  private func assertFoldedExprStructure(
    _ source: String,
    _ expected: String,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    let expr = sequenceExpr(source)
    let folded = expr.folded(context: context)

    let writer = SequenceExprStructureWriter()
    writer.walk(folded)
    XCTAssertEqual(writer.result, expected, file: file, line: line)
  }

  /// Parses and returns a sequence expression from a Swift source string.
  ///
  /// - Precondition: The first code block of `source` is a statement containing
  ///   a `SequenceExprSyntax`. All subsequent code blocks are ignored.
  private func sequenceExpr(_ source: String) -> SequenceExprSyntax {
    let sourceFileSyntax = try! Parser.parse(source: source)
    return sourceFileSyntax.statements.first!.item.as(SequenceExprSyntax.self)!
  }
}

/// Returns a string representation of a folded sequence expression that can be
/// compared for testing.
///
/// Any `SequenceExpr` or `TernaryExpr` in the syntax tree will be surrounded by
/// curly braces (`{ ... }`). Other tokens will be printed with a preceding
/// space (except for the first character in the output).
fileprivate class SequenceExprStructureWriter: SyntaxVisitor {

  /// The string containing the concatenated output.
  private(set) var result = ""

  init() {
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
    open()
    return .visitChildren
  }

  override func visitPost(_ node: SequenceExprSyntax) {
    close()
  }

  override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
    open()
    return .visitChildren
  }

  override func visitPost(_ node: TernaryExprSyntax) {
    close()
  }

  override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    if !result.isEmpty { result += " " }
    result += token.text
    return .skipChildren
  }

  override func visitPost(_ node: TokenSyntax) {}

  private func open() {
    if let last = result.last, last != "{" { result += " " }
    result += "{"
  }

  private func close() {
    if let last = result.last, last != "}" { result += " " }
    result += "}"
  }
}
