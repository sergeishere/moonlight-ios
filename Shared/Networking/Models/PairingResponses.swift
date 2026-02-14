import Foundation

struct StartPairingResponse: Decodable {
    let plainCert: String
    let paired: Int

    enum CodingKeys: String, CodingKey {
        case paired
        case plainCert = "plaincert"
    }
}

struct ServerChallengeResponse: Decodable {
    let challengeResponse: String

    enum CodingKeys: String, CodingKey {
        case challengeResponse = "challengeresponse"
    }
}

struct ServerSecretResponse: Decodable {
    let pairingSecret: String

    enum CodingKeys: String, CodingKey {
        case pairingSecret = "pairingsecret"
    }
}

struct PairChallengeResponse: Decodable {
    let paired: Int
}
