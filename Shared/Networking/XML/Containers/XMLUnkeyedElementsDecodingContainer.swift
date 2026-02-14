import Foundation
import Clibxml2

struct XMLUnkeyedElementsDecodingContainer: UnkeyedDecodingContainer {

    var children: [xmlNodePtr]

    var userInfo: [CodingUserInfoKey: Any]
    var codingPath: [any CodingKey]

    var count: Int? { children.count }
    var currentIndex: Int = 0
    var isAtEnd: Bool { currentIndex >= count ?? 0 }

    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        let decoder = _XMLDecoder(
            node: children[currentIndex],
            codingPath: codingPath,
            userInfo: userInfo
        )
        currentIndex += 1
        return try T(from: decoder)
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
