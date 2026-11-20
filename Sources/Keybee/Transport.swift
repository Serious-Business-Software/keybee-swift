import Foundation

/// keybee's answer to a device request. The grant carries the same facts as
/// the rest of the reply, signed, so only it is used for decisions.
struct DeviceReply: Decodable, Sendable, Equatable {
    let result: String
    let activation_id: String?
    let grant: String
}

protocol Transport: Sendable {
    func send(_ operation: DeviceOperation, _ body: DeviceRequest) async throws(KeybeeError) -> DeviceReply
}

struct URLSessionTransport: Transport {
    static let userAgent = "keybee-swift/0.1.0"

    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func send(_ operation: DeviceOperation, _ body: DeviceRequest) async throws(KeybeeError) -> DeviceReply {
        var request = URLRequest(url: baseURL.appendingPathComponent("v2").appendingPathComponent(operation.rawValue))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw .network(error.code)
        } catch {
            throw .network(.unknown)
        }

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        let requestID = http?.value(forHTTPHeaderField: "Keybee-Request-Id")
        guard status == 200 else {
            struct ErrorBody: Decodable { struct Inner: Decodable { let code: String? }; let error: Inner }
            let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.code
            throw .server(status: status, code: code, requestID: requestID)
        }
        guard let reply = try? JSONDecoder().decode(DeviceReply.self, from: data) else {
            throw .server(status: 200, code: "unparsable_reply", requestID: requestID)
        }
        return reply
    }
}
