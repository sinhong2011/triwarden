import Foundation

/// The ChaCha20 stream cipher (RFC 8439) on its own, without Poly1305: KeePass files use it for the payload and
/// for protected values inside it. CryptoKit only offers it sealed with Poly1305, so it lives here.
public struct ChaCha20 {
    private var state: [UInt32]
    private var block = [UInt8](repeating: 0, count: 64)
    private var used = 64

    /// A 32-byte key and a 12-byte nonce; `counter` is the first block's number.
    public init(key: Data, nonce: Data, counter: UInt32 = 0) {
        precondition(key.count == 32 && nonce.count == 12, "ChaCha20 needs a 32-byte key and a 12-byte nonce")
        // Little-endian 32-bit words, built step by step: one long shift-or chain is too slow to type-check
        // on older compilers.
        func words(_ d: Data) -> [UInt32] {
            let b = [UInt8](d)
            var out: [UInt32] = []
            out.reserveCapacity(b.count / 4)
            var i = 0
            while i < b.count {
                var w = UInt32(b[i])
                w |= UInt32(b[i + 1]) << 8
                w |= UInt32(b[i + 2]) << 16
                w |= UInt32(b[i + 3]) << 24
                out.append(w)
                i += 4
            }
            return out
        }
        state = [0x6170_7865, 0x3320_646E, 0x7962_2D32, 0x6B20_6574] + words(key) + [counter] + words(nonce)
    }

    /// XORs `data` with the next bytes of the key stream. The stream carries on across calls.
    public mutating func apply(_ data: Data) -> Data {
        var out = [UInt8](data)
        for i in out.indices {
            if used == 64 { nextBlock() }
            out[i] ^= block[used]
            used += 1
        }
        return Data(out)
    }

    private mutating func nextBlock() {
        var x = state
        @inline(__always) func quarter(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            x[a] &+= x[b]; x[d] ^= x[a]; x[d] = x[d] << 16 | x[d] >> 16
            x[c] &+= x[d]; x[b] ^= x[c]; x[b] = x[b] << 12 | x[b] >> 20
            x[a] &+= x[b]; x[d] ^= x[a]; x[d] = x[d] << 8 | x[d] >> 24
            x[c] &+= x[d]; x[b] ^= x[c]; x[b] = x[b] << 7 | x[b] >> 25
        }
        for _ in 0..<10 {
            quarter(0, 4, 8, 12); quarter(1, 5, 9, 13); quarter(2, 6, 10, 14); quarter(3, 7, 11, 15)
            quarter(0, 5, 10, 15); quarter(1, 6, 11, 12); quarter(2, 7, 8, 13); quarter(3, 4, 9, 14)
        }
        for i in 0..<16 {
            let w = x[i] &+ state[i]
            block[i * 4] = UInt8(truncatingIfNeeded: w)
            block[i * 4 + 1] = UInt8(truncatingIfNeeded: w >> 8)
            block[i * 4 + 2] = UInt8(truncatingIfNeeded: w >> 16)
            block[i * 4 + 3] = UInt8(truncatingIfNeeded: w >> 24)
        }
        state[12] &+= 1
        used = 0
    }
}
