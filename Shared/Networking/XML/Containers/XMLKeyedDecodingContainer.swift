import Foundation
import Clibxml2

struct XMLKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {

    var node: xmlNodePtr
    var children: [String: xmlNodePtr]

    var allKeys: [Key]
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any]

    init(
        node: xmlNodePtr,
        codingPath: [any CodingKey] = [],
        allKeys: [Key] = [],
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) {
        self.node = node
        self.codingPath = codingPath
        self.allKeys = allKeys
        self.userInfo = userInfo
        self.children = [:]

        var currentChild = node.pointee.children
        while let child = currentChild {
            if child.pointee.type == XML_ELEMENT_NODE {
                let key = String(cString: child.pointee.name)
                children[key] = child
            }
            currentChild = child.pointee.next
        }
    }

    func contains(_ key: Key) -> Bool {
        children[key.stringValue] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        children[key.stringValue] == nil
    }

    func decodeFromString<T>(_ type: T.Type, forKey key: Key) throws -> T where T: LosslessStringConvertible {
        let context = DecodingError.Context(codingPath: codingPath, debugDescription: "Key '\(key.stringValue)' not found")

        guard let childNode = children[key.stringValue]
        else { throw DecodingError.keyNotFound(key, context) }

        guard let nodeContent = xmlNodeGetContent(childNode)
        else { throw DecodingError.valueNotFound(type, context) }
        defer { xmlSafeFree(nodeContent) }

        let stringContent = String(cString: nodeContent)

        guard let value = T(stringContent)
        else { throw DecodingError.typeMismatch(type, context) }
        return value
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        let intValue: Int = try decodeFromString(Int.self, forKey: key)
        return intValue != 0
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        try decodeFromString(type, forKey: key)
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        try decodeFromString(type, forKey: key)
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {

        guard let childNode = children[key.stringValue]
        else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Key '\(key.stringValue)' not found"
            ))
        }

        var newCodingPath = codingPath
        newCodingPath.append(key)

        if type == URL.self {

            guard let nodeContent = xmlNodeGetContent(childNode)
            else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(
                    codingPath: newCodingPath,
                    debugDescription: "URL not found."
                ))
            }
            defer { xmlSafeFree(nodeContent) }

            let stringContent = String(cString: nodeContent)

            guard let url = URL(string: stringContent) as? T
            else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: newCodingPath,
                    debugDescription: "Invalid URL string."
                ))
            }
            return url
        }

        let decoder = _XMLDecoder(node: childNode, codingPath: newCodingPath, userInfo: userInfo)
        return try T(from: decoder)
    }

    func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        fatalError("nestedContainer not implemented")
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        fatalError("nestedUnkeyedContainer not implemented")
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        fatalError("superDecoder not implemented")
    }

    func superDecoder() throws -> any Decoder {
        fatalError("superDecoder not implemented")
    }
}
