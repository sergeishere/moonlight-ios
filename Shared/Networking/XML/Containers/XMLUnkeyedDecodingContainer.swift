import Foundation
import Clibxml2

struct XMLUnkeyedDecodingContainer: UnkeyedDecodingContainer {

    var content: String

    var userInfo: [CodingUserInfoKey: Any]
    var codingPath: [any CodingKey]

    var count: Int? { content.count / 2 }

    var currentIndex: Int = 0
    var isAtEnd: Bool { currentIndex >= count ?? 0 }

    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable, T: FixedWidthInteger {

        let context = DecodingError.Context(codingPath: codingPath, debugDescription: "")

        let size = MemoryLayout<T>.size * 2
        let startIndex = content.index(content.startIndex, offsetBy: currentIndex)
        let endIndex = content.index(startIndex, offsetBy: size)
        let substring = content[startIndex..<endIndex]

        guard let value = T(substring, radix: 16)
        else { throw DecodingError.typeMismatch(type, context) }

        currentIndex += size

        return value
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        fatalError("decode<T>(_ type: \(type)) not implemented")
    }

    mutating func decodeNil() throws -> Bool {
        fatalError("decodeNil not implemented")
    }

    mutating func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        fatalError("nestedContainer keyedBy \(type) not implemented")
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        fatalError("nestedUnkeyedContainer not implemented")
    }

    mutating func superDecoder() throws -> any Decoder {
        fatalError("superDecoder not implemented")
    }
}
