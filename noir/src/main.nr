fn main(
    hashed_message: pub [Field; 2],
    pub_key_x: pub [Field; 2],
    pub_key_y: pub [Field; 2],
    signature_r: pub [Field; 2],
    signature_s: pub [Field; 2],
) {
    // Unpack field arrays back to 32-byte arrays (reverse of pack_bytes)
    let hashed_message_bytes = unpack_fields_to_32_bytes(hashed_message);
    let pub_key_x_bytes = unpack_fields_to_32_bytes(pub_key_x);
    let pub_key_y_bytes = unpack_fields_to_32_bytes(pub_key_y);
    let signature_r_bytes = unpack_fields_to_32_bytes(signature_r);
    let signature_s_bytes = unpack_fields_to_32_bytes(signature_s);
    
    // Combine r and s into signature array
    let mut signature: [u8; 64] = [0; 64];
    for i in 0..32 {
        signature[i] = signature_r_bytes[i];
        signature[i + 32] = signature_s_bytes[i];
    }
    
    let valid = std::ecdsa_secp256r1::verify_signature(
        pub_key_x_bytes,
        pub_key_y_bytes,
        signature,
        hashed_message_bytes
    );
    assert(valid);
}

// Unpack field array back to 32-byte array (reverse of pack_bytes)
// Assumes input is 2 field elements: [31 bytes, 1 byte padded]
fn unpack_fields_to_32_bytes(fields: [Field; 2]) -> [u8; 32] {
    let mut result: [u8; 32] = [0; 32];
    
    // First field contains bytes 0-30 (31 bytes)
    let first_chunk_bytes: [u8; 32] = fields[0].to_le_bytes();
    for i in 0..31 {
        result[i] = first_chunk_bytes[i]; // Take bytes 0-30 (little-endian order)
    }
    
    // Second field contains byte 31 (1 byte, with padding)
    let second_chunk_bytes: [u8; 32] = fields[1].to_le_bytes();
    result[31] = second_chunk_bytes[0]; // Take the first byte (least significant in little-endian)
    
    result
}
