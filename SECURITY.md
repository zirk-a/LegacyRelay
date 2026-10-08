# Session-file security

The `.mgsession` format uses Argon2id with 64 MiB of memory and three passes, followed by XChaCha20-Poly1305 authenticated encryption. Each export has independently generated random salt and nonce values.

The archive username and password are separate from the website credentials. Both values are required to derive the file key. A predictable username contributes little additional resistance to password guessing, so use a strong, unique file password.

The encrypted archive protects stored session content when its file credentials remain secret. It does not protect an already unlocked device, a compromised application, or a session invalidated by the website.

Do not include session files, credentials, cookie values or decrypted profiles in issue reports. To report a security vulnerability, contact the repository maintainer privately.
