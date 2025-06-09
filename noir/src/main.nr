fn main(
    hashed_message: pub Field,
    pub_key_x: pub Field,
    pub_key_y: pub Field,
    signature_r: pub Field,
    signature_s: pub Field,
) {
    // Convert signature fields to byte arrays
    let r_bytes: [u8; 32] = signature_r.to_be_bytes();
    let s_bytes: [u8; 32] = signature_s.to_be_bytes();
    
    let valid = std::ecdsa_secp256r1::verify_signature(
        pub_key_x.to_be_bytes::<32>(),
        pub_key_y.to_be_bytes::<32>(),
        r_bytes.concat(s_bytes),
        hashed_message.to_be_bytes::<32>(),
    );
    assert(valid);
}
