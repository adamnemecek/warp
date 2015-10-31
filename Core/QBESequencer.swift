import Foundation
import SwiftParser

/** The sequencer generates series of values based on a pattern that looks like a regex. For example, the sequencer with
formula "[abc]" will generate values "a", "b" and "c". The syntax is as follows:

- ab: a follows b (e.g. ["ab"])
- a|b: a or b (["a","b"])
- a?: a or nothing (["a",""]). Note that unlike regexes the '?' operator applies to the full string before it (e.g. 
  'test?' will generate 'test'  and '').
- [abc]: a, b or c (["a","b","c"])
- [a-z]: any character from a to z inclusive (["a"..."z"])
- (a): subsequence

The sequencer will return any possible combination, e.g. [abc][def] will lead to a sequence of the values ad,ae,af...cf.
*/
public class QBESequencer: Parser {
	private let reservedCharacters: [Character] = ["[", "]", "(", ")", "-", "\\", "'", "|", "?", "{", "}"]
	private let specialCharacters: [Character: Character] = [
		"t": "\t",
		"n": "\n",
		"r": "\r"
	]
	private var stack = QBEStack<QBEValueSequence>()
	
	public init?(_ formula: String) {
		super.init()
		if !self.parse(formula) {
			return nil
		}
	}
	
	public var randomValue: QBEValue? {
		get {
			return stack.head.random()
		}
	}
	
	public var root: AnySequence<QBEValue>? {
		get {
			return AnySequence(stack.head)
		}
	}
	
	public var cardinality: Int? {
		get {
			return stack.head.cardinality
		}
	}
	
	private func pushFollowing() {
		let r = stack.pop()
		let l = stack.pop()
		stack.push(QBECombinatorSequence(left: l, right: r))
	}
	
	private func pushAfter() {
		let then = stack.pop()
		let first = stack.pop()
		stack.push(QBEAfterSequence(first: first, then: then))
	}
	
	private func pushCharset() {
		stack.push(QBEValueSetSequence())
	}
	
	private func pushValue() {
		if let r = stack.head as? QBEValueSetSequence {
			r.values.append(QBEValue(unescape(self.text)))
		}
		else {
			fatalError("Not supported!")
		}
	}
	
	private func unescape(var text: String) -> String {
		for reserved in reservedCharacters {
			text = text.stringByReplacingOccurrencesOfString("\\\(reserved)", withString: String(reserved))
		}
		
		for (specialBefore, specialAfter) in specialCharacters {
			text = text.stringByReplacingOccurrencesOfString("\\\(specialBefore)", withString: String(specialAfter))
		}
		return text
	}
	
	private func pushString() {
		let text = unescape(self.text)
		stack.push(QBEValueSetSequence([QBEValue(text)]))
	}
	
	private func pushMaybe() {
		let r = stack.pop()
		stack.push(QBEMaybeSequence(r))
	}
	
	private func pushRepeat() {
		if let n = self.text.toInt() {
			let r = stack.pop()
			stack.push(QBERepeatSequence(r, count: n))
		}
	}
	
	private func pushRange() {
		if let r = stack.head as? QBEValueSetSequence {
			let items = self.text.componentsSeparatedByString("-")
			assert(items.count == 2, "Invalid range")
			let startChar: unichar = items[0].utf16.first!
			let endChar: unichar = items[1].utf16.first!
			
			if endChar > startChar {
				for character in startChar...endChar {
					r.values.append(QBEValue(String(Character(UnicodeScalar(character)))))
				}
			}
		}
		else {
			fatalError("Not supported!")
		}
	}
	
	public override func rules() {
		let reservedCharactersRule = Parser.matchAnyFrom(reservedCharacters.map({ return Parser.matchLiteralInsensitive(String($0)) }))
		let specialCharactersRule = Parser.matchAnyFrom(specialCharacters.keys.map({ return Parser.matchLiteralInsensitive(String($0)) }))
		let escapes = Parser.matchLiteralInsensitive("\\") ~~ (reservedCharactersRule | specialCharactersRule)
		
		add_named_rule("number", rule: (("0" - "9")++))
		add_named_rule("escapedCharacter", rule: escapes => pushValue)
		add_named_rule("character", rule: (Parser.matchAnyCharacterExcept(reservedCharacters) => pushValue))
		add_named_rule("string", rule: ((Parser.matchAnyCharacterExcept(reservedCharacters) | escapes)++ => pushString))
		add_named_rule("charRange", rule: (Parser.matchAnyCharacterExcept(reservedCharacters) ~~ "-" ~~ Parser.matchAnyCharacterExcept(reservedCharacters)) => pushRange)
		add_named_rule("charSpec", rule: (^"charRange" | ^"escapedCharacter" | ^"character")*)
		
		add_named_rule("charset", rule: ((Parser.matchLiteralInsensitive("[") => pushCharset) ~~ ^"charSpec" ~~ "]"))
		add_named_rule("component", rule: ^"subsequence" | ^"charset" | ^"string")
		add_named_rule("maybe", rule: ^"component" ~~ (Parser.matchLiteralInsensitive("?") => pushMaybe)/~)
		add_named_rule("repeat", rule: ^"maybe" ~~ (Parser.matchLiteralInsensitive("{") ~~ (^"number" => pushRepeat) ~~ Parser.matchLiteralInsensitive("}"))/~)
		
		add_named_rule("following", rule: ^"repeat" ~~ ((^"repeat") => pushFollowing)*)
		add_named_rule("alternatives", rule: ^"following" ~~ (("|" ~~ ^"following") => pushAfter)*)
		add_named_rule("subsequence", rule: "(" ~~ ^"alternatives" ~~ ")")
		
		start_rule = ^"alternatives"
	}
	
	public func stream(column: QBEColumn) -> QBEStream {
		return QBESequenceStream(AnySequence<QBEFallible<QBETuple>>({ () -> QBESequencerRowGenerator in
			return QBESequencerRowGenerator(source: self.root!)
		}), columnNames: [column], rowCount: stack.head.cardinality)
	}
}

private class QBEValueGenerator: AnyGenerator<QBEValue> {
	override func next() -> Element? {
		return nil
	}
}

private class QBEProxyValueGenerator<G: GeneratorType where G.Element == QBEValue>: QBEValueGenerator {
	private var generator: G
	
	init(_ generator: G) {
		self.generator = generator
	}
	
	override func next() -> QBEValue? {
		return generator.next()
	}
}

private class QBEValueSequence: SequenceType {
	typealias Generator = QBEValueGenerator
	
	func random() -> QBEValue? {
		fatalError("This should never be called")
	}
	
	func generate() -> QBEValueGenerator {
		return QBEValueGenerator()
	}
	
	/** The number of elements this sequence will generate. Nil indicates that the length of this sequence is unknown
	(e.g. very large or infinite) */
	var cardinality: Int? { get {
		return 0
	} }
}

private class QBEValueSetSequence: QBEValueSequence {
	var values: [QBEValue] = []
	
	override init() {
	}
	
	init(_ values: [QBEValue]) {
		self.values = values
	}
	
	private override func random() -> QBEValue? {
		return Array(values).randomElement
	}
	
	override func generate() -> Generator {
		return QBEProxyValueGenerator(values.generate())
	}
	
	override var cardinality: Int { get {
		return values.count
	} }
}

private class QBEMaybeGenerator: QBEValueGenerator {
	var generator: QBEValueGenerator? = nil
	let sequence: QBEValueSequence
	
	init(_ sequence: QBEValueSequence) {
		self.sequence = sequence
	}
	
	private override func next() -> QBEValue? {
		if let g = generator {
			return g.next()
		}
		else {
			generator = sequence.generate()
			return QBEValue("")
		}
	}
}

private class QBERepeatGenerator: QBEValueGenerator {
	var generators: [QBEValueGenerator] = []
	var values: [QBEValue] = []
	let sequence: QBEValueSequence
	var done = false
	
	init(_ sequence: QBEValueSequence, count: Int) {
		self.sequence = sequence
		for _ in 0..<count {
			let gen = sequence.generate()
			self.generators.append(gen)
			values.append(gen.next() ?? QBEValue.InvalidValue)
		}
		self.generators[self.generators.count-1] = sequence.generate()
	}
	
	private override func next() -> QBEValue? {
		if done {
			return nil
		}

		// Increment
		for i in 0..<generators.count {
			let index = generators.count - i - 1
			let generator = generators[index]
			if let next = generator.next() {
				values[index] = next
				break
			}
			else {
				if index == 0 {
					done = true
					return nil
				}
				
				generators[index] = sequence.generate()
				values[index] = generators[index].next() ?? QBEValue.InvalidValue
				// And do not break, go on to increment next (carry)
			}
		}
		
		// Return value
		return QBEValue(values.map({ return $0.stringValue ?? "" }).joinWithSeparator(""))
	}
}

private class QBERepeatSequence: QBEValueSequence {
	let sequence: QBEValueSequence
	let repeatCount: Int
	
	init(_ sequence: QBEValueSequence, count: Int) {
		self.sequence = sequence
		self.repeatCount = count
	}
	
	private override func random() -> QBEValue? {
		var str = QBEValue("")
		for _ in 0..<repeatCount {
			str = str & (self.sequence.random() ?? QBEValue.InvalidValue)
		}
		return str
	}
	
	private override func generate() -> QBEValueGenerator {
		return QBERepeatGenerator(sequence, count: repeatCount)
	}
	
	
	override var cardinality: Int? { get {
		if let base = sequence.cardinality {
			let d = pow(Double(base), Double(repeatCount))
			if d > Double(Int.max) {
				return nil
			}
			return Int(d)
		}
		return nil
	} }
	
}

private class QBEMaybeSequence: QBEValueSequence {
	let sequence: QBEValueSequence
	
	init(_ sequence: QBEValueSequence) {
		self.sequence = sequence
	}
	
	private override func random() -> QBEValue? {
		if Bool.random {
			return QBEValue("")
		}
		return self.sequence.random()
	}
	
	private override func generate() -> QBEValueGenerator {
		return QBEMaybeGenerator(sequence)
	}
	
	override var cardinality: Int { get {
		return 2
	} }
}

private class QBECombinatorGenerator: QBEValueGenerator {
	private var leftGenerator: QBEValueGenerator
	private var rightGenerator: QBEValueGenerator
	private let rightSequence: QBEValueSequence
	private var leftValue: QBEValue?
	
	init(left: QBEValueSequence, right: QBEValueSequence) {
		self.leftGenerator = left.generate()
		self.rightGenerator = right.generate()
		self.rightSequence = right
		self.leftValue = self.leftGenerator.next()
	}
	
	override func next() -> QBEValue? {
		if let l = leftValue {
			// Fetch a new right value
			if let r = self.rightGenerator.next() {
				return l & r
			}
			else {
				// need a new left value, reset right value
				self.rightGenerator = self.rightSequence.generate()
				leftValue = self.leftGenerator.next()
				return next()
			}
		}
		else {
			return nil
		}
	}
}

private class QBEAfterGenerator: QBEValueGenerator {
	private var firstGenerator: QBEValueGenerator
	private var thenGenerator: QBEValueGenerator
	
	init(first: QBEValueSequence, then: QBEValueSequence) {
		self.firstGenerator = first.generate()
		self.thenGenerator = then.generate()
	}
	
	override func next() -> QBEValue? {
		if let l = firstGenerator.next() {
			return l
		}
		else {
			return thenGenerator.next()
		}
	}
}

private class QBECombinatorSequence: QBEValueSequence {
	let left: QBEValueSequence
	let right: QBEValueSequence
	
	init(left: QBEValueSequence, right: QBEValueSequence) {
		self.left = left
		self.right = right
	}
	
	private override func random() -> QBEValue? {
		if let a = left.random(), b = right.random() {
			return a & b
		}
		return nil
	}
	
	override func generate() -> QBEValueGenerator {
		return QBECombinatorGenerator(left: self.left, right: self.right)
	}
	
	override var cardinality: Int? { get {
		if let l = left.cardinality, let r = right.cardinality {
			return l * r
		}
		return nil
	} }
}

private class QBEAfterSequence: QBEValueSequence {
	let first: QBEValueSequence
	let then: QBEValueSequence
	
	init(first: QBEValueSequence, then: QBEValueSequence) {
		self.first = first
		self.then = then
	}
	
	private override func random() -> QBEValue? {
		if Bool.random {
			return first.random()
		}
		else {
			return then.random()
		}
	}
	
	override func generate() -> QBEValueGenerator {
		return QBEAfterGenerator(first: self.first, then: self.then)
	}
	
	override var cardinality: Int? { get {
		if let f = first.cardinality, let s = then.cardinality {
			return f + s
		}
		return nil
	} }
}

private class QBESequencerRowGenerator: GeneratorType {
	let source: AnyGenerator<QBEValue>
	typealias Element = QBEFallible<QBETuple>
	
	init(source: AnySequence<QBEValue>) {
		self.source = source.generate()
	}
	
	func next() -> QBEFallible<QBETuple>? {
		if let n = source.next() {
			return .Success([n])
		}
		return nil
	}
}