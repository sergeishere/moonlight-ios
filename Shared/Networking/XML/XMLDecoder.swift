import Foundation
import Clibxml2

public struct XMLDecoder {

    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    public func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {

        guard let xmlDocument = data.withUnsafeBytes({ pointer in
            xmlReadMemory(pointer.baseAddress, Int32(data.count), nil, nil, 0)
        })
        else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Not valid XML")) }
        defer { xmlFreeDoc(xmlDocument) }

        guard let rootNode = xmlDocGetRootElement(xmlDocument)
        else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Root node is missing")) }

        return try decode(type, from: rootNode)
    }

    public func decode<T>(_ type: T.Type, from node: xmlNodePtr) throws -> T where T: Decodable {
        let decoder = _XMLDecoder(node: node, codingPath: [], userInfo: userInfo)
        return try T.init(from: decoder)
    }
}

struct _XMLDecoder: Decoder {

    let node: xmlNodePtr
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any]

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        KeyedDecodingContainer(XMLKeyedDecodingContainer(node: node, codingPath: codingPath, userInfo: userInfo))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let childNodesCount = Int(xmlChildElementCount(node))
        if childNodesCount != 0 {
            var children = [xmlNodePtr]()
            var currentChild = node.pointee.children
            while let child = currentChild {
                if child.pointee.type == XML_ELEMENT_NODE {
                    children.append(child)
                }
                currentChild = child.pointee.next
            }
            return XMLUnkeyedElementsDecodingContainer(
                children: children,
                userInfo: userInfo,
                codingPath: codingPath
            )
        } else if let nodeContent = xmlNodeGetContent(node) {
            defer { xmlSafeFree(nodeContent) }
            return XMLUnkeyedDecodingContainer(
                content: String(cString: nodeContent),
                userInfo: userInfo,
                codingPath: codingPath
            )
        }
        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Cannot create unkeyed container"
        ))
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        XMLSingleValueDecodingContainer(node: node, codingPath: codingPath)
    }
}
