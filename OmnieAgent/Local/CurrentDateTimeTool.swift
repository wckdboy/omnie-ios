import Foundation
import FoundationModels

/// The one tool available to the on-device agent. Without it, the model has
/// no way to know what day or time it actually is — this is what makes the
/// on-device assistant a genuine (if small) agent rather than a plain chatbot.
struct CurrentDateTimeTool: Tool {
    let name = "currentDateTime"
    let description = "Returns the current date and time on the user's iPhone, including the time zone."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        return formatter.string(from: Date())
    }
}
