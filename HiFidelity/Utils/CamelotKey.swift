//
//  CamelotKey.swift
//  HiFidelity
//
//  Utility for converting musical keys to Camelot Wheel notation
//  The Camelot Wheel is a DJ tool that maps keys to numbers for easy mixing
//

import Foundation

/// Camelot Wheel key notation (1A-12A for minor, 1B-12B for major)
struct CamelotKey: Codable, Equatable, Hashable {
    let number: Int  // 1-12
    let isMinor: Bool  // true = A (minor), false = B (major)
    
    var notation: String {
        "\(number)\(isMinor ? "A" : "B")"
    }
    
    var displayName: String {
        notation
    }
    
    /// Initialize from standard key notation (0-11 for key, 0=minor/1=major for mode)
    /// Standard notation: 0=C, 1=C#, 2=D, 3=D#, 4=E, 5=F, 6=F#, 7=G, 8=G#, 9=A, 10=A#, 11=B
    init?(key: Int, mode: Int) {
        guard key >= 0 && key <= 11 else { return nil }
        guard mode == 0 || mode == 1 else { return nil }
        
        // Camelot Wheel mapping
        // Minor keys (mode 0): A notation
        // Major keys (mode 1): B notation
        let camelotMap: [Int: (minor: Int, major: Int)] = [
            0: (5, 8),   // C -> 5A/8B
            1: (12, 3),   // C# -> 12A/3B
            2: (7, 10),   // D -> 7A/10B
            3: (2, 5),    // D# -> 2A/5B
            4: (9, 12),   // E -> 9A/12B
            5: (4, 7),    // F -> 4A/7B
            6: (11, 2),   // F# -> 11A/2B
            7: (6, 9),    // G -> 6A/9B
            8: (1, 4),    // G# -> 1A/4B
            9: (8, 11),   // A -> 8A/11B
            10: (3, 6),   // A# -> 3A/6B
            11: (10, 1)   // B -> 10A/1B
        ]
        
        guard let mapping = camelotMap[key] else { return nil }
        
        if mode == 0 {
            // Minor key
            self.number = mapping.minor
            self.isMinor = true
        } else {
            // Major key
            self.number = mapping.major
            self.isMinor = false
        }
    }
    
    /// Initialize from Camelot notation string (e.g., "5A", "8B")
    init?(notation: String) {
        guard notation.count >= 2 else { return nil }
        
        let suffix = notation.suffix(1).uppercased()
        guard suffix == "A" || suffix == "B" else { return nil }
        
        let numberString = String(notation.dropLast())
        guard let number = Int(numberString), number >= 1 && number <= 12 else { return nil }
        
        self.number = number
        self.isMinor = (suffix == "A")
    }
    
    /// Get compatible keys for mixing (same key, +1, -1, and relative major/minor)
    var compatibleKeys: [CamelotKey] {
        var keys: [CamelotKey] = [self]
        
        // Same key (perfect match)
        keys.append(self)
        
        // Adjacent keys on the wheel (+1 and -1, wrapping around)
        let nextNumber = (number % 12) + 1
        let prevNumber = number == 1 ? 12 : number - 1
        
        keys.append(CamelotKey(number: nextNumber, isMinor: isMinor))
        keys.append(CamelotKey(number: prevNumber, isMinor: isMinor))
        
        // Relative major/minor (same number, opposite mode)
        keys.append(CamelotKey(number: number, isMinor: !isMinor))
        
        return Array(Set(keys)) // Remove duplicates
    }
    
    /// Check if two keys are compatible for mixing
    func isCompatible(with other: CamelotKey) -> Bool {
        // Same key
        if self == other {
            return true
        }
        
        // Adjacent keys
        let diff = abs(self.number - other.number)
        if (diff == 1 || diff == 11) && self.isMinor == other.isMinor {
            return true
        }
        
        // Relative major/minor (same number, opposite mode)
        if self.number == other.number && self.isMinor != other.isMinor {
            return true
        }
        
        return false
    }
}

extension CamelotKey {
    /// Initialize directly from number and mode
    init(number: Int, isMinor: Bool) {
        guard number >= 1 && number <= 12 else {
            // Default to 1A if invalid
            self.number = 1
            self.isMinor = true
            return
        }
        self.number = number
        self.isMinor = isMinor
    }
}

/// Display format for musical keys
enum KeyDisplayFormat: String, CaseIterable {
    case note = "Note"           // e.g., Dm, D, E♭m, E♭
    case openKey = "Open Key"    // e.g., 7d, 7m (d=minor, m=major)
    case altKey = "Camelot Key"      // e.g., 12A, 12B (A=minor, B=major) - Camelot Wheel

    var userDefaultsKey: String {
        "keyDisplayFormat"
    }
}

/// Helper to convert standard key notation to display string
struct KeyNotation {
    // Sharp notation (used for display)
    static let keyNamesSharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // Flat notation (alternative, more common in some keys)
    static let keyNamesFlat = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    // Map of which keys typically use flat notation
    // Keys that are commonly written as flats: D♭, E♭, G♭, A♭, B♭
    static let preferFlat: Set<Int> = [1, 3, 6, 8, 10]

    /// Get display name based on format preference
    static func displayName(key: Int, mode: Int, format: KeyDisplayFormat = .note) -> String {
        guard key >= 0 && key <= 11 else { return "Unknown" }

        switch format {
        case .note:
            // Use flat notation for keys that typically use flats
            let keyName = preferFlat.contains(key) ? keyNamesFlat[key] : keyNamesSharp[key]
            let modeName = mode == 0 ? "m" : ""
            return "\(keyName)\(modeName)"

        case .openKey:
            // Open Key notation: number + d/m (d=minor, m=major)
            guard let camelot = CamelotKey(key: key, mode: mode) else { return "Unknown" }
            let suffix = mode == 0 ? "d" : "m"
            return "\(camelot.number)\(suffix)"

        case .altKey:
            // Camelot Key (Camelot) notation: number + A/B (A=minor, B=major)
            guard let camelot = CamelotKey(key: key, mode: mode) else { return "Unknown" }
            return camelot.notation
        }
    }

    /// Convert to Camelot notation string
    static func camelotNotation(key: Int, mode: Int) -> String? {
        guard let camelot = CamelotKey(key: key, mode: mode) else { return nil }
        return camelot.notation
    }

    /// Get sort order for key (0-23, where 0-11 are major keys, 12-23 are minor keys)
    static func sortOrder(key: Int, mode: Int) -> Int {
        guard key >= 0 && key <= 11 else { return 999 }
        // Sort major keys first (0-11), then minor keys (12-23)
        return mode == 1 ? key : key + 12
    }
}

