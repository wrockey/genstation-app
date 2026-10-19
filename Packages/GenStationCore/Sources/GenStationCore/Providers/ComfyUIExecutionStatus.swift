import Foundation

public enum ComfyUIExecutionStatus {
    public static func failureMessage(_ status: [String: Any]) -> String? {
        for message in status["messages"] as? [[Any]] ?? [] {
            guard let kind = message.first as? String,
                  ["execution_error", "execution_interrupted"].contains(kind) else { continue }
            let details = message.count > 1 ? message[1] as? [String: Any] : nil
            let reason = details?["exception_message"] as? String
            return "ComfyUI execution failed: " + (reason ?? (kind == "execution_interrupted" ? "The job was interrupted." : "Check the server log for details."))
        }
        return status["status_str"] as? String == "error" ? "ComfyUI execution failed. Check the server log for details." : nil
    }
}
