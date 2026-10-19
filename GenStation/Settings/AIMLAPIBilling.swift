// AIMLAPIBilling.swift (Updated with Fallback & Full Logging)

import Foundation
import GenStationCore

// Structured response types (matches exact docs format)
struct AIMLBalanceResponse: Codable {
    let balance: Int  // Docs: Always present as Int (e.g., 10000000 for 10M credits)
    let lowBalance: Bool?
    let lowBalanceThreshold: Int?
    let lastUpdated: String?
    let autoDebitStatus: String?
    let status: String?
    let statusExplanation: String?
    
    // Convenience: Convert balance to Double for your UI
    var balanceDouble: Double { Double(balance) }
}

struct AIMLBalanceError: Codable, Error {
    let error: String?
    let message: String?
}

func fetchBalance(apiKey: String) async throws -> [String: Any] {
    // Primary endpoint (per docs)
    let primaryURL = AIMLEndpoints.balanceURL.absoluteString
    // Fallback (possible migration to main API)
    let fallbackURL = AIMLEndpoints.balanceFallbackURL.absoluteString
    
    for (attempt, urlString) in [(1, primaryURL), (2, fallbackURL)] {
        guard let url = URL(string: urlString) else {
            Log.debug("Attempt \(attempt): Invalid URL \(urlString)")
            continue
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")  // Required per docs
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Log HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                Log.debug("Attempt \(attempt) (\(urlString)): HTTP Status: \(statusCode)")
                
                if statusCode == 200 {
                    // Success — parse below
                } else if statusCode == 401 {
                    throw GenerationError.apiError("Invalid AIMLAPI key (401 Unauthorized)")
                } else if statusCode == 404 {
                    Log.debug("Attempt \(attempt): 404 Not Found — trying fallback...")
                    if attempt == 2 {  // Last attempt failed
                        throw GenerationError.apiError("Billing endpoint not found (404) — check AIMLAPI status")
                    }
                    continue  // Try next URL
                } else if statusCode >= 400 && statusCode < 500 {
                    let body = String(data: data, encoding: .utf8) ?? "No body"
                    throw GenerationError.apiError("Client error (\(statusCode)): \(body)")
                } else if statusCode >= 500 {
                    throw GenerationError.apiError("Server error (\(statusCode)) — try again later")
                }
            }
            
            // Log raw response (UTF-8 or hex for binary/debug)
            if let rawBody = String(data: data, encoding: .utf8) {
                Log.debug("Attempt \(attempt) Raw Response: \(rawBody)")
            } else {
                let hexPreview = data.prefix(200).map { String(format: "%02x", $0) }.joined(separator: " ")
                Log.debug("Attempt \(attempt) Raw Response: Binary (\(data.count) bytes) — hex preview: \(hexPreview)...")
            }
            
            // Parse as structured response
            let decoder = JSONDecoder()
            let balanceResponse = try decoder.decode(AIMLBalanceResponse.self, from: data)
            
            // Convert to [String: Any] for your UI (backward compat)
            var result: [String: Any] = [
                "balance": balanceResponse.balanceDouble,
                "lowBalance": balanceResponse.lowBalance ?? false,
                "lastUpdated": balanceResponse.lastUpdated ?? ""
            ]
            
            // Add optional fields
            if let threshold = balanceResponse.lowBalanceThreshold {
                result["lowBalanceThreshold"] = threshold
            }
            if let autoDebit = balanceResponse.autoDebitStatus {
                result["autoDebitStatus"] = autoDebit
            }
            if let status = balanceResponse.status {
                result["status"] = status
            }
            if let explanation = balanceResponse.statusExplanation {
                result["statusExplanation"] = explanation
            }
            
            Log.debug("Balance fetched successfully: \(balanceResponse.balanceDouble) credits")
            return result
            
        } catch DecodingError.keyNotFound(let key, let context) {
            Log.debug("Decoding error (Attempt \(attempt)): Missing key '\(key.stringValue)' at path: \(context.codingPath)")
            if attempt == 2 {
                throw GenerationError.apiError("Invalid balance response format (missing field)")
            }
            continue
        } catch DecodingError.typeMismatch(let type, let context) {
            Log.debug("Decoding error (Attempt \(attempt)): Expected \(type) at path: \(context.codingPath)")
            if attempt == 2 {
                throw GenerationError.apiError("Invalid balance response format (type mismatch)")
            }
            continue
        } catch let error as URLError {
            Log.debug("Network error (Attempt \(attempt)): \(error.localizedDescription)")
            if attempt == 2 {
                throw error
            }
            continue
        } catch {
            Log.debug("Unexpected error (Attempt \(attempt)): \(error.localizedDescription)")
            if attempt == 2 {
                throw GenerationError.apiError("Failed to parse balance: \(error.localizedDescription)")
            }
            continue
        }
    }
    
    // If all attempts fail
    throw GenerationError.apiError("All balance endpoints failed — check network or AIMLAPI status")
}
