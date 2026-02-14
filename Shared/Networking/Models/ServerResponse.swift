import Foundation
import Clibxml2

struct ServerResponse<Content: Decodable> {
    let content: Content
    let statusCode: Int
    let statusMessage: String?

    init(from data: Data) throws {

        guard let doc = data.withUnsafeBytes({ unsafeRawBufferPointer in
            xmlReadMemory(unsafeRawBufferPointer.baseAddress, Int32(data.count), nil, nil, 0)
        })
        else { throw ServerResponseError.xmlParsing }
        defer { xmlFreeDoc(doc) }

        guard let rootNode = xmlDocGetRootElement(doc)
        else { throw ServerResponseError.xmlParsing }

        if let cStatusCode = xmlGetProp(rootNode, "status_code") {
            let statusCodeString = String(cString: cStatusCode)
            xmlSafeFree(cStatusCode)
            self.statusCode = Int(statusCodeString) ?? 0
        } else {
            self.statusCode = 0
        }

        if let cStatusMessage = xmlGetProp(rootNode, "status_message") {
            self.statusMessage = String(cString: cStatusMessage)
            xmlSafeFree(cStatusMessage)
        } else {
            self.statusMessage = nil
        }

        self.content = try XMLDecoder().decode(Content.self, from: rootNode)
    }

    var isStatusOk: Bool {
        statusCode == 200
    }
}

enum ServerResponseError: LocalizedError {
    case xmlParsing
    case serverError(Int, String?)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .xmlParsing:
            return "Failed to parse server XML response"
        case .serverError(let code, let message):
            return message ?? "Server error (code: \(code))"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}
