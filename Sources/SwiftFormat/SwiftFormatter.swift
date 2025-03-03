//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftFormatConfiguration
import SwiftFormatCore
import SwiftFormatPrettyPrint
import SwiftFormatRules
import SwiftSyntax
import SwiftParser
import SwiftDiagnostics

/// Formats Swift source code or syntax trees according to the Swift style guidelines.
public final class SwiftFormatter {

  /// The configuration settings that control the formatter's behavior.
  public let configuration: Configuration

  /// An optional callback that will be notified with any findings encountered during formatting.
  public let findingConsumer: ((Finding) -> Void)?

  /// Advanced options that are useful when debugging the formatter's behavior but are not meant for
  /// general use.
  public var debugOptions: DebugOptions = []

  /// Creates a new Swift code formatter with the given configuration.
  ///
  /// - Parameters:
  ///   - configuration: The configuration settings that control the formatter's behavior.
  ///   - findingConsumer: An optional callback that will be notified with any findings encountered
  ///     during formatting. Unlike the `Linter` API, this defaults to nil for formatting because
  ///     findings are typically less useful than the final formatted output.
  public init(configuration: Configuration, findingConsumer: ((Finding) -> Void)? = nil) {
    self.configuration = configuration
    self.findingConsumer = findingConsumer
  }

  /// Formats the Swift code at the given file URL and writes the result to an output stream.
  ///
  /// - Parameters:
  ///   - url: The URL of the file containing the code to format.
  ///   - outputStream: A value conforming to `TextOutputStream` to which the formatted output will
  ///     be written.
  ///   - parsingDiagnosticHandler: An optional callback that will be notified if there are any
  ///     errors when parsing the source code.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func format<Output: TextOutputStream>(
    contentsOf url: URL,
    to outputStream: inout Output,
    parsingDiagnosticHandler: ((Diagnostic, SourceLocation) -> Void)? = nil
  ) throws {
    guard FileManager.default.isReadableFile(atPath: url.path) else {
      throw SwiftFormatError.fileNotReadable
    }
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
      throw SwiftFormatError.isDirectory
    }
    let source = try String(contentsOf: url, encoding: .utf8)
    let sourceFile = try Parser.parse(source: source)
    if let parsingDiagnosticHandler = parsingDiagnosticHandler {
      let expectedConverter = SourceLocationConverter(file: url.path, tree: sourceFile)
      let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: sourceFile)
      for diagnostic in diagnostics {
        let location = diagnostic.location(converter: expectedConverter)
        parsingDiagnosticHandler(diagnostic, location)
      }
    }
    try format(syntax: sourceFile, assumingFileURL: url, source: source, to: &outputStream)
  }

  /// Formats the given Swift source code and writes the result to an output stream.
  ///
  /// - Parameters:
  ///   - source: The Swift source code to be formatted.
  ///   - url: A file URL denoting the filename/path that should be assumed for this syntax tree,
  ///     which is associated with any diagnostics emitted during formatting. If this is nil, a
  ///     dummy value will be used.
  ///   - outputStream: A value conforming to `TextOutputStream` to which the formatted output will
  ///     be written.
  ///   - parsingDiagnosticHandler: An optional callback that will be notified if there are any
  ///     errors when parsing the source code.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func format<Output: TextOutputStream>(
    source: String,
    assumingFileURL url: URL?,
    to outputStream: inout Output,
    parsingDiagnosticHandler: ((Diagnostic, SourceLocation) -> Void)? = nil
  ) throws {
    let sourceFile = try Parser.parse(source: source)
    if let parsingDiagnosticHandler = parsingDiagnosticHandler {
      let expectedConverter = SourceLocationConverter(file: url?.path ?? "<unknown>", tree: sourceFile)
      let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: sourceFile)
      for diagnostic in diagnostics {
        let location = diagnostic.location(converter: expectedConverter)
        parsingDiagnosticHandler(diagnostic, location)
      }
    }
    try format(syntax: sourceFile, assumingFileURL: url, source: source, to: &outputStream)
  }

  /// Formats the given Swift syntax tree and writes the result to an output stream.
  ///
  /// - Note: The formatter may be faster using the source text, if it's available.
  ///
  /// - Parameters:
  ///   - syntax: The Swift syntax tree to be converted to source code and formatted.
  ///   - url: A file URL denoting the filename/path that should be assumed for this syntax tree,
  ///     which is associated with any diagnostics emitted during formatting. If this is nil, a
  ///     dummy value will be used.
  ///   - outputStream: A value conforming to `TextOutputStream` to which the formatted output will
  ///     be written.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func format<Output: TextOutputStream>(
    syntax: SourceFileSyntax, assumingFileURL url: URL?, to outputStream: inout Output
  ) throws {
    try format(syntax: syntax, assumingFileURL: url, source: nil, to: &outputStream)
  }

  private func format<Output: TextOutputStream>(
    syntax: SourceFileSyntax, assumingFileURL url: URL?, source: String?,
    to outputStream: inout Output
  ) throws {
    if let position = _firstInvalidSyntaxPosition(in: Syntax(syntax)) {
      throw SwiftFormatError.fileContainsInvalidSyntax(position: position)
    }

    let assumedURL = url ?? URL(fileURLWithPath: "source")
    let context = Context(
      configuration: configuration, findingConsumer: findingConsumer, fileURL: assumedURL,
      sourceFileSyntax: syntax, source: source, ruleNameCache: ruleNameCache)
    let pipeline = FormatPipeline(context: context)
    let transformedSyntax = pipeline.visit(Syntax(syntax))

    if debugOptions.contains(.disablePrettyPrint) {
      outputStream.write(transformedSyntax.description)
      return
    }

    let operatorContext = OperatorContext.makeBuiltinOperatorContext()
    let printer = PrettyPrinter(
      context: context,
      operatorContext: operatorContext,
      node: transformedSyntax,
      printTokenStream: debugOptions.contains(.dumpTokenStream),
      whitespaceOnly: false)
    outputStream.write(printer.prettyPrint())
  }
}
