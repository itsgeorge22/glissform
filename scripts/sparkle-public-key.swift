import CryptoKit
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let encoded = String(data: input, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      let seed = Data(base64Encoded: encoded), seed.count == 32 else {
    fputs("Expected Sparkle's exported 32-byte EdDSA private seed.\n", stderr)
    exit(1)
}

let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
print(key.publicKey.rawRepresentation.base64EncodedString())
