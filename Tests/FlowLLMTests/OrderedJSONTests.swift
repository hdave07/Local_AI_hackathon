import FlowCore
@testable import FlowLLM
import Foundation
import Testing

@Suite("Deterministic schema wire order")
struct OrderedJSONTests {
    @Test func schemaPropertiesFollowFieldOrder() throws {
        let text = String(decoding: IntentSchema.jsonSchema.serialized(), as: UTF8.self)
        let properties = try #require(text.range(of: "\"properties\":"))
        let tail = text[properties.upperBound...]
        let positions = IntentSchema.fields.map { tail.range(of: "\"\($0)\":")!.lowerBound }
        #expect(positions == positions.sorted(), "properties must appear in IntentSchema.fields order")
    }

    @Test func requestBodyIsByteIdenticalAcrossCalls() async throws {
        let transport = MockTransport([Fixtures.completion(Fixtures.intentJSON(action: "scroll", detail: "down")),
                                       Fixtures.completion(Fixtures.intentJSON(action: "scroll", detail: "down"))])
        let classifier = Fixtures.classifier(transport)
        _ = try await classifier.classify("scroll down")
        _ = try await classifier.classify("scroll down")
        let bodies = transport.requests.map(\.httpBody)
        #expect(bodies.count == 2)
        #expect(bodies[0] == bodies[1])
    }

    @Test func serializationIsValidJSONWithEscaping() throws {
        let tricky = "quote \" backslash \\ newline \n tab \t bell \u{07} émoji 🎙"
        let value: OrderedJSON = .object([
            ("s", .string(tricky)), ("n", .int(-3)), ("b", .bool(true)), ("z", .null),
            ("a", .array([.int(1), .string("x")])),
        ])
        let parsed = try #require(JSONSerialization.jsonObject(with: value.serialized()) as? [String: Any])
        #expect(parsed["s"] as? String == tricky)
        #expect(parsed["n"] as? Int == -3)
        #expect(parsed["b"] as? Bool == true)
        #expect(parsed["z"] is NSNull)
        #expect((parsed["a"] as? [Any])?.count == 2)
    }

    @Test func schemaStillDeclaresStrictAllowlists() throws {
        let schema = try #require(JSONSerialization.jsonObject(with: IntentSchema.jsonSchema.serialized()) as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(Set(schema["required"] as? [String] ?? []) == Set(IntentSchema.fields))
        let props = try #require(schema["properties"] as? [String: [String: Any]])
        #expect(Set(props["action"]?["enum"] as? [String] ?? []) == Set(IntentSchema.allowedActionNames))
        #expect(Set(props["kind"]?["enum"] as? [String] ?? []) == Set(IntentKind.modelEmittable.map(\.rawValue)))
    }
}
