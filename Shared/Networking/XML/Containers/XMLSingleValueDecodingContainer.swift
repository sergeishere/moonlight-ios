import Foundation
import Clibxml2

struct XMLSingleValueDecodingContainer: SingleValueDecodingContainer {

    var node: xmlNodePtr
    var codingPath: [any CodingKey]

    func decodeNil() -> Bool {
        true
    }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable, T: LosslessStringConvertible {
        let context = DecodingError.Context(codingPath: codingPath, debugDescription: "")

        guard let nodeContent = xmlNodeGetContent(node)
        else { throw DecodingError.valueNotFound(type, context) }
        defer { xmlSafeFree(nodeContent) }

        let stringContent = String(cString: nodeContent)

        guard let value = T(stringContent)
        else { throw DecodingError.typeMismatch(type, context) }
        return value
    }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        fatalError("decode \(type) not implemented")
    }
}
