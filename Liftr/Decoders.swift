import Foundation

extension JSONDecoder {
    static func supabaseCustom() -> JSONDecoder {
        let decoder = JSONDecoder()
        
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let isoNoFraction = ISO8601DateFormatter()
        isoNoFraction.formatOptions = [.withInternetDateTime]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            
            if container.decodeNil() { return Date(timeIntervalSince1970: 0) }
            
            if let str = try? container.decode(String.self) {
                if let d1 = isoWithFraction.date(from: str) { return d1 }
                if let d2 = isoNoFraction.date(from: str) { return d2 }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601: \(str)")
            }
            
            if let num = try? container.decode(Double.self) {
                let secs = num > 10_000_000_000 ? num / 1000.0 : num
                return Date(timeIntervalSince1970: secs)
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date format")
        }
        
        return decoder
    }
}
