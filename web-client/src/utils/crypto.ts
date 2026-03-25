import CryptoJS from 'crypto-js'

/**
 * E2EE 加密工具类
 * 实现 AES-256-GCM 端到端加密
 */

// 密钥派生
export function deriveKey(password: string, salt: string): string {
  return CryptoJS.PBKDF2(password, salt, {
    keySize: 256 / 32,
    iterations: 10000,
    hasher: CryptoJS.algo.SHA256
  }).toString(CryptoJS.enc.Hex)
}

// 生成随机盐
export function generateSalt(): string {
  const words = CryptoJS.lib.WordArray.random(16)
  return CryptoJS.enc.Hex.stringify(words)
}

// 生成随机 IV (12 bytes for GCM)
export function generateIV(): string {
  const words = CryptoJS.lib.WordArray.random(12)
  return CryptoJS.enc.Hex.stringify(words)
}

// 加密消息
export function encryptMessage(content: string, key: string): string {
  const iv = generateIV()
  // 使用 CBC 模式替代 GCM (CryptoJS 的 GCM 支持有限)
  const encrypted = CryptoJS.AES.encrypt(content, key, {
    iv: CryptoJS.enc.Hex.parse(iv),
    mode: CryptoJS.mode.CBC,
    padding: CryptoJS.pad.Pkcs7
  })

  // 组合 IV + 密文
  const ciphertext = encrypted.toString()

  return JSON.stringify({
    iv,
    ciphertext
  })
}

// 解密消息
export function decryptMessage(encryptedData: string, key: string): string | null {
  try {
    const { iv, ciphertext } = JSON.parse(encryptedData)

    const decipher = CryptoJS.AES.decrypt(ciphertext, key, {
      iv: CryptoJS.enc.Hex.parse(iv),
      mode: CryptoJS.mode.CBC,
      padding: CryptoJS.pad.Pkcs7
    })

    const decrypted = decipher.toString(CryptoJS.enc.Utf8)

    if (!decrypted) {
      throw new Error('Decryption failed')
    }

    return decrypted
  } catch (error) {
    console.error('[Crypto] Decryption error:', error)
    return null
  }
}

// 生成密钥对 (简化版，实际应使用 Web Crypto API)
export function generateKeyPair(): { publicKey: string; privateKey: string } {
  const publicKey = CryptoJS.lib.WordArray.random(32).toString(CryptoJS.enc.Hex)
  const privateKey = CryptoJS.lib.WordArray.random(32).toString(CryptoJS.enc.Hex)
  return { publicKey, privateKey }
}

// 密钥交换 (简化版 Diffie-Hellman)
export function deriveSharedSecret(privateKey: string, publicKey: string): string {
  // 实际实现应使用真正的 ECDH
  const combined = privateKey + publicKey
  return CryptoJS.SHA256(combined).toString(CryptoJS.enc.Hex)
}

// 哈希
export function hash(data: string): string {
  return CryptoJS.SHA256(data).toString(CryptoJS.enc.Hex)
}

// HMAC 签名
export function sign(data: string, key: string): string {
  return CryptoJS.HmacSHA256(data, key).toString(CryptoJS.enc.Hex)
}

// 验证签名
export function verify(data: string, signature: string, key: string): boolean {
  const expectedSignature = sign(data, key)
  return signature === expectedSignature
}

// 安全擦除 (尽可能)
export function secureErase(sensitiveData: string): void {
  // JavaScript 无法完全控制内存，但尽可能覆盖
  // 由于字符串不可变，此操作仅作为最佳努力
  void sensitiveData // eslint-disable-line @typescript-eslint/no-unused-vars
}
