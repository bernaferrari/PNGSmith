import Foundation

struct NormalizedCrop: Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = NormalizedCrop(x: 0, y: 0, width: 1, height: 1)
}

/// A transparent output canvas positioned relative to the source image.
struct CanvasEdit: Hashable, Sendable {
    var canvas: NormalizedCrop
    var aspect: CropAspect

    static let full = CanvasEdit(canvas: .full, aspect: .free)

    var isIdentity: Bool {
        abs(canvas.x) < 0.000_1 && abs(canvas.y) < 0.000_1
            && abs(canvas.width - 1) < 0.000_1 && abs(canvas.height - 1) < 0.000_1
    }

    func pixelOptions(imageWidth: Int, imageHeight: Int) -> CanvasOptions {
        let outputWidth = max(Int((canvas.width * Double(imageWidth)).rounded()), 1)
        let outputHeight = max(Int((canvas.height * Double(imageHeight)).rounded()), 1)
        return CanvasOptions(
            width: outputWidth,
            height: outputHeight,
            imageScale: 1,
            imageOffsetX: Int((-canvas.x * Double(imageWidth)).rounded()),
            imageOffsetY: Int((-canvas.y * Double(imageHeight)).rounded())
        )
    }
}

enum CropAspect: String, CaseIterable, Identifiable, Sendable {
    case free = "Free"
    case square = "Square"
    case fourThree = "4:3"
    case sixteenNine = "16:9"
    case twoOne = "2:1"

    var id: Self { self }

    var ratio: Double? {
        switch self {
        case .free: nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .sixteenNine: 16.0 / 9.0
        case .twoOne: 2
        }
    }
}

/// Evaluates the small arithmetic expressions accepted by crop dimension fields.
/// Deliberately supports only numbers, parentheses, and the four basic operators.
enum CropDimensionExpression {
    static func pixels(from expression: String) -> Int? {
        var parser = Parser(expression)
        guard let value = parser.parse(), value.isFinite, value > 0,
              value <= Double(Int.max) else {
            return nil
        }
        let pixels = Int(value.rounded())
        return pixels > 0 ? pixels : nil
    }

    private struct Parser {
        private let characters: [Character]
        private var index = 0

        init(_ source: String) {
            characters = Array(
                source
                    .replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: "×", with: "*")
                    .replacingOccurrences(of: "÷", with: "/")
            )
        }

        mutating func parse() -> Double? {
            guard let value = parseExpression() else { return nil }
            skipWhitespace()
            return index == characters.count ? value : nil
        }

        private mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while true {
                skipWhitespace()
                if consume("+") {
                    guard let rhs = parseTerm() else { return nil }
                    value += rhs
                } else if consume("-") {
                    guard let rhs = parseTerm() else { return nil }
                    value -= rhs
                } else {
                    return value
                }
            }
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parseUnary() else { return nil }
            while true {
                skipWhitespace()
                if consume("*") {
                    guard let rhs = parseUnary() else { return nil }
                    value *= rhs
                } else if consume("/") {
                    guard let rhs = parseUnary(), rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    return value
                }
            }
        }

        private mutating func parseUnary() -> Double? {
            skipWhitespace()
            if consume("+") { return parseUnary() }
            if consume("-") { return parseUnary().map { -$0 } }
            return parsePrimary()
        }

        private mutating func parsePrimary() -> Double? {
            skipWhitespace()
            if consume("(") {
                guard let value = parseExpression() else { return nil }
                skipWhitespace()
                guard consume(")") else { return nil }
                return value
            }
            return parseNumber()
        }

        private mutating func parseNumber() -> Double? {
            skipWhitespace()
            let start = index
            var hasDigit = false
            var hasDecimalPoint = false

            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    hasDigit = true
                    index += 1
                } else if character == ".", !hasDecimalPoint {
                    hasDecimalPoint = true
                    index += 1
                } else {
                    break
                }
            }

            guard hasDigit else { return nil }
            return Double(String(characters[start..<index]))
        }

        private mutating func skipWhitespace() {
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
        }

        private mutating func consume(_ character: Character) -> Bool {
            guard index < characters.count, characters[index] == character else {
                return false
            }
            index += 1
            return true
        }
    }
}
