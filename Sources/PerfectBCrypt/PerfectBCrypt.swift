import bcrypt
import Foundation

open class BCrypt {

  public enum SaltPrefixType:String {
    case _2A = "2a"
    case _2B = "2b"
  }

  public enum Exception: Error {
    case InvalidRounds
    case RandomAllocationFault
    case UTF8Fault
    case Unsupported
    case InvalidSalt
    case InvalidPassword
    case KDFault
    case RandomDeviceFault
  }

  public static func RandomArray<T>(count: Int) throws ->[T] {
    guard let frandom = fopen("/dev/urandom", "rb") else {
      throw Exception.RandomDeviceFault
    }
    let size = MemoryLayout<T>.size * count
    var buf = UnsafeMutablePointer<T>.allocate(capacity: size)
    defer { buf.deallocate(capacity: size) }
    guard size == fread(buf, MemoryLayout<T>.size, count, frandom) else {
      throw Exception.RandomAllocationFault
    }
    _ = fclose(frandom)
    let array = UnsafeMutableBufferPointer<T>(start: buf, count: count)
    return Array(array)
  }
  /// Generate salt based on the settings
  /// - parameters:
  ///   - prefix: 2A or 2B
  ///   - rounds: a number in [4, 31]
  /// - returns: a salted string.
  /// - throws: Exception
  public static func Salt(_ prefix: SaltPrefixType = ._2B,
                             rounds: Int = 12) throws -> String {
    guard rounds > 3 && rounds < 32 else {
      throw Exception.InvalidRounds
    }
    let salt:[UInt8] = try RandomArray(count:16)
    let size = 30
    let outputPointer = UnsafeMutablePointer<Int8>.allocate(capacity: size)
    defer { outputPointer.deallocate(capacity: size) }
    _ = encode_base64(outputPointer, salt, 16)
    guard let output = String(validatingUTF8: outputPointer) else {
      throw Exception.RandomAllocationFault
    }
    let rnd = String(format: "%2.2u", rounds)
    return "$" + prefix.rawValue +  "$" + rnd + "$" + output
  }

  /// Generate shadow by password and salt
  /// - parameters:
  ///   - password: the password to hash
  ///   - salt: the salt to add with
  /// - returns: a salted password
  /// - throws: Exception
  public static func Hash(_ password: String, salt: String) throws -> String {
    let size = 128
    let hashed = UnsafeMutablePointer<Int8>.allocate(capacity: size)
    defer { hashed.deallocate(capacity: size) }
    guard 0 == bcrypt_hashpass(password, salt, hashed, size) else {
      throw Exception.InvalidSalt
    }
    guard let ret = (salt.withCString { pSalt -> String? in
      memcpy(hashed, pSalt, 4)
      return String(validatingUTF8: hashed)
    }) else { throw Exception.UTF8Fault }
    return ret
  }

  public static func KDF(_ password: String, salt: String, desiredKeyBytes: Int, rounds: UInt32, ignoreFewRounds: Bool = false) throws -> [UInt8] {
    guard !password.isEmpty else {
      throw Exception.InvalidPassword
    }
    guard !salt.isEmpty else {
      throw Exception.InvalidSalt
    }
    guard desiredKeyBytes > 0 && desiredKeyBytes <= 513 else {
      throw Exception.Unsupported
    }
    guard rounds > 0 else {
      throw Exception.InvalidRounds
    }
    if !ignoreFewRounds {
      guard rounds > 49 else {
        throw Exception.InvalidRounds
      }
    }
    let key = UnsafeMutablePointer<UInt8>.allocate(capacity: desiredKeyBytes)
    defer { key.deallocate(capacity: desiredKeyBytes) }
    guard 0 == bcrypt_pbkdf(password, password.count, salt, salt.count, key, desiredKeyBytes, rounds) else {
      throw Exception.KDFault
    }
    let buf = UnsafeMutableBufferPointer<UInt8>(start: key, count: desiredKeyBytes)
    return Array(buf)
  }

  #if os(Linux)
  /// Verify if the password matches the hashed string
  /// - parameters:
  ///   - password: a password to test with
  ///   - hashed: a hashed string to test
  /// - returns:
  ///   True if matches.
  public static func Check(_ password: String, hashed: String) -> Bool {
    do {
      let ret = try Hash(password, salt: hashed)
      guard ret.count == hashed.count else {
        return false
      }
      return 0 == timingsafe_bcmp(ret, hashed, ret.count)
    }catch {
      return false
    }
  }
  #else
  /// Verify if the password matches the hashed string
  /// - parameters:
  ///   - password: a password to test with
  ///   - hashed: a hashed string to test
  /// - returns:
  ///   True if matches.
    @available(iOS 10.1, *)
    @available(OSX 10.12.1, *)
  public static func Check(_ password: String, hashed: String) -> Bool {
    do {
      let ret = try Hash(password, salt: hashed)
      guard ret.count == hashed.count else {
        return false
      }
      return 0 == timingsafe_bcmp(ret, hashed, ret.count)
    }catch {
      return false
    }
  }
  #endif

}
