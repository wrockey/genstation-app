import Foundation

/// Exact USD representation at the provider's 10^-10 dollar precision.
/// JSON-facing callers should use decimal/tick strings, not floating-point sums.
public struct ExactUSD: Codable, Equatable, Sendable {
    public let ticks: UInt64
    public init(ticks: UInt64) { self.ticks = ticks }
    public init(decimal: String) throws {
        guard decimal.range(of: "^[0-9]+(?:\\.[0-9]{1,10})?$", options: .regularExpression) != nil else { throw AgentImageError("Invalid exact USD amount.") }
        let parts = decimal.split(separator: ".", omittingEmptySubsequences: false)
        guard let dollars = UInt64(parts[0]) else { throw AgentImageError("USD amount overflows.") }
        let product = dollars.multipliedReportingOverflow(by: 10_000_000_000)
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let remainder = UInt64(fraction + String(repeating: "0", count: 10 - fraction.count)) ?? 0
        let sum = product.partialValue.addingReportingOverflow(remainder)
        guard !product.overflow, !sum.overflow else { throw AgentImageError("USD amount overflows.") }
        ticks = sum.partialValue
    }
    public var decimal: String {
        let fraction = String(ticks % 10_000_000_000)
        return "\(ticks / 10_000_000_000)." + String(repeating: "0", count: 10 - fraction.count) + fraction
    }
    public var displayUSD: Double { Double(ticks) / 10_000_000_000 }
    public func adding(_ other: ExactUSD) throws -> ExactUSD {
        let result = ticks.addingReportingOverflow(other.ticks)
        guard !result.overflow else { throw AgentImageError("USD total overflows.") }
        return ExactUSD(ticks: result.partialValue)
    }
}

public struct ProviderChargeEvidence: Codable, Equatable, Sendable {
    public let provider: Provider
    public let amount: ExactUSD
    public let field: String
    public let httpStatus: Int
    public var json: [String: Any] {
        ["provider": provider.rawValue, "currency": "USD", "amount_usd": amount.decimal,
         "usd_ticks": String(amount.ticks), "source": "provider_response_usage", "field": field,
         "http_status": httpStatus, "reconciliation": "not_independently_reconciled"]
    }
    public struct Observation: Sendable {
        public let evidence: ProviderChargeEvidence?
        public let unavailableReason: String?
    }
    private struct Usage: Decodable {
        let usd_spent: Decimal?
        let cost_in_usd_ticks: UInt64?
        let currency: String?
    }
    private struct Envelope: Decodable {
        let usage: Usage?
        let meta: Meta?
        struct Meta: Decodable { let usage: Usage? }
    }
    /// Only request-scoped response fields are read; body/prompt/credentials are never retained.
    /// An absent/malformed field is unknown, including on HTTP errors. This is not a quote.
    public static func observe(provider: Provider, data: Data, httpStatus: Int) -> Observation {
        guard provider == .aimlapi || provider == .grok else { return Observation(evidence: nil, unavailableReason: "provider_usage_adapter_unavailable") }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            let usages = [envelope.meta?.usage, envelope.usage].compactMap { $0 }
            guard usages.allSatisfy({ $0.currency == nil || $0.currency == "USD" }) else { return Observation(evidence: nil, unavailableReason: "unsupported_currency") }
            let amounts: [ExactUSD]
            let field: String
            if provider == .grok {
                amounts = envelope.usage?.cost_in_usd_ticks.map { [ExactUSD(ticks: $0)] } ?? []
                field = "usage.cost_in_usd_ticks"
            } else {
                amounts = try usages.compactMap { usage in
                    guard var decimal = usage.usd_spent else { return nil }
                    return try ExactUSD(decimal: NSDecimalString(&decimal, Locale(identifier: "en_US_POSIX")))
                }
                field = envelope.meta?.usage?.usd_spent != nil ? "meta.usage.usd_spent" : "usage.usd_spent"
            }
            guard let amount = amounts.first else { return Observation(evidence: nil, unavailableReason: "usage_missing") }
            guard amounts.allSatisfy({ $0 == amount }) else { return Observation(evidence: nil, unavailableReason: "conflicting_usage") }
            return Observation(evidence: ProviderChargeEvidence(provider: provider, amount: amount, field: field, httpStatus: httpStatus), unavailableReason: nil)
        } catch { return Observation(evidence: nil, unavailableReason: "usage_malformed_or_out_of_range") }
    }
}
