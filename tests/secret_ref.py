#!/usr/bin/env python3
"""Reference values for the pairing-secret known-answer test in flowtest.m, computed with hashlib alone.

The secret is SHA-256(client modulus || client exponent || server modulus || server exponent || last two bytes of the code),
and the first byte of the code must equal the first byte of that hash. Run this file to see the values flowtest.m expects."""
import hashlib

CLIENT_MODULUS = bytes([0x01, 0x02, 0x03])
CLIENT_EXPONENT = bytes([0x04, 0x05])
SERVER_MODULUS = bytes([0x01, 0x02, 0x03])
SERVER_EXPONENT = bytes([0x04, 0x05])
NONCE = bytes([0xAB, 0xCD])      # the two bytes of the code after the check byte

digest = hashlib.sha256(CLIENT_MODULUS + CLIENT_EXPONENT + SERVER_MODULUS + SERVER_EXPONENT + NONCE).digest()
print("code   =", f"{digest[0]:02X}" + NONCE.hex().upper())
print("secret =", digest.hex())
