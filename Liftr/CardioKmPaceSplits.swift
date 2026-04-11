import Foundation
import Supabase

enum CardioKmPaceSplits {
    static let jsonKey = "km_split_pace_sec"

    static func formatFieldText(secondsPerKm splits: [Int]) -> String {
        splits.map { sec in
            let m = sec / 60
            let s = sec % 60
            return String(format: "%d:%02d", m, s)
        }.joined(separator: ", ")
    }

    static func parseFieldText(_ text: String) -> [Int] {
        let raw = text
            .replacingOccurrences(of: "·", with: ",")
            .replacingOccurrences(of: ";", with: ",")
        let parts = raw.split { $0.isNewline || $0 == "," }.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var out: [Int] = []
        out.reserveCapacity(parts.count)
        for p in parts {
            let token = p.lowercased().replacingOccurrences(of: "/km", with: "").trimmingCharacters(in: .whitespaces)
            if let sec = parseSingleToken(token), sec > 0 {
                out.append(sec)
            }
        }
        return out
    }

    private static func parseSingleToken(_ token: String) -> Int? {
        if token.allSatisfy({ $0.isNumber }) {
            return Int(token)
        }
        let bits = token.split(separator: ":").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard bits.count >= 2, bits.count <= 3 else { return nil }
        let nums = bits.compactMap { Int($0) }
        guard nums.count == bits.count else { return nil }
        switch nums.count {
        case 2:
            return nums[0] * 60 + nums[1]
        case 3:
            return nums[0] * 3600 + nums[1] * 60 + nums[2]
        default:
            return nil
        }
    }

    static func mergedStatsForUpsert(existingRowData: Data?, kmSplitsPaceSec: [Int]) throws -> AnyJSON {
        var dict = statsDictionary(fromSingleRowData: existingRowData)
        if kmSplitsPaceSec.isEmpty {
            dict.removeValue(forKey: jsonKey)
        } else {
            dict[jsonKey] = kmSplitsPaceSec
        }
        let anyDict = try dictionaryToAnyJSONMap(dict)
        return try AnyJSON(anyDict)
    }

    private static func statsDictionary(fromSingleRowData data: Data?) -> [String: Any] {
        guard let data, !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        if let stats = root["stats"] as? [String: Any] {
            return stats
        }
        return [:]
    }

    private static func dictionaryToAnyJSONMap(_ dict: [String: Any]) throws -> [String: AnyJSON] {
        var out: [String: AnyJSON] = [:]
        out.reserveCapacity(dict.count)
        for (k, v) in dict {
            out[k] = try anyJSON(from: v)
        }
        return out
    }

    private static func anyJSON(from value: Any) throws -> AnyJSON {
        switch value {
        case let i as Int:
            return try AnyJSON(i)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return try AnyJSON(n.boolValue)
            }
            if n.doubleValue.rounded() == n.doubleValue,
               n.doubleValue >= Double(Int.min), n.doubleValue <= Double(Int.max) {
                return try AnyJSON(n.intValue)
            }
            return try AnyJSON(n.doubleValue)
        case let d as Double:
            return try AnyJSON(d)
        case let f as Float:
            return try AnyJSON(Double(f))
        case let s as String:
            return try AnyJSON(s)
        case let b as Bool:
            return try AnyJSON(b)
        case let arr as [Int]:
            return try AnyJSON(arr.map { try AnyJSON($0) })
        case let arr as [Any]:
            return try AnyJSON(arr.map { try anyJSON(from: $0) })
        case let arr as NSArray:
            return try AnyJSON((0..<arr.count).map { try anyJSON(from: arr[$0]) })
        case let nested as [String: Any]:
            return try AnyJSON(dictionaryToAnyJSONMap(nested))
        default:
            throw NSError(domain: "CardioKmPaceSplits", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported JSON value type"])
        }
    }
}
