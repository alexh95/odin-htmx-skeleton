# platform/totp

One-time codes (PLAN §17.1, Q11): RFC 6238 over RFC 4226, HMAC-SHA1, 30-second steps, 6 digits, the parameters every
authenticator app defaults to. A secret is 20 random bytes, shown as unpadded base32 and in the `otpauth://` text for
manual entry (no QR encoder). `verify` accepts the step either side of now, for a phone's clock, and names the step
that matched, so the caller can refuse a code twice. The unit tests hold both RFCs' vectors. Layer L2 (PLAN §5.1).
