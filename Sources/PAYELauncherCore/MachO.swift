import Foundation

/// Reads the CPU architectures of a Mach-O executable (thin or universal).
public enum MachO {
    static let cpuTypeX86: UInt32 = 0x0100_0007
    static let cpuTypeARM: UInt32 = 0x0100_000C

    public static func architectures(of url: URL) -> Set<String> {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 4096)
        return architectures(header: header)
    }

    public static func architectures(header data: Data) -> Set<String> {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return [] }
        func bigEndian(_ offset: Int) -> UInt32? {
            guard offset + 4 <= bytes.count else { return nil }
            return bytes[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        func littleEndian(_ offset: Int) -> UInt32? {
            guard offset + 4 <= bytes.count else { return nil }
            return bytes[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }

        switch bigEndian(0) {
        case 0xCAFE_BABE, 0xCAFE_BABF:  // universal (fat), 32- or 64-bit offsets
            let entrySize = bigEndian(0) == 0xCAFE_BABE ? 20 : 32
            guard let count = bigEndian(4), count < 64 else { return [] }
            var result = Set<String>()
            for index in 0..<Int(count) {
                if let cpu = bigEndian(8 + index * entrySize), let name = name(of: cpu) { result.insert(name) }
            }
            return result
        default:
            guard littleEndian(0) == 0xFEED_FACF, let cpu = littleEndian(4), let name = name(of: cpu) else { return [] }
            return [name]
        }
    }

    static func name(of cpuType: UInt32) -> String? {
        switch cpuType {
        case cpuTypeX86: return "x86_64"
        case cpuTypeARM: return "arm64"
        default: return nil
        }
    }
}
