use clap::Parser;
use p256::ecdsa::{SigningKey, Signature, signature::Signer};
use rand::rngs::OsRng;
use serde::Serialize;
use std::fs;
use std::path::Path;
use num_bigint::{BigUint, ToBigUint};
use sha2::{Sha256, Digest};

/// CLI Arguments
#[derive(Parser, Debug)]
#[command(author, version, about)]
struct Args {
    /// Number of test cases to generate
    #[arg(short, long, default_value_t = 10)]
    num_test_cases: usize,
}

/// Test case data for snarkjs/rapidsnark
#[derive(Serialize)]
struct SnarkjsTestCase {
    r: Vec<String>,
    s: Vec<String>,
    msghash: Vec<String>,
    pubkey: Vec<Vec<String>>,
}

/// Pack bytes into Field elements (implements the same logic as Noir's pack_bytes)
/// Splits input into 31-byte chunks and converts each to a Field element
fn pack_bytes(bytes: &[u8]) -> Vec<String> {
    let n = bytes.len();
    let num_chunks = n / 31 + 1; // Matches Noir's N / 31 + 1
    
    // Pad bytes to (num_chunks * 31) length - matches Noir's pad_end
    let padded_len = num_chunks * 31;
    let mut bytes_padded = bytes.to_vec();
    bytes_padded.resize(padded_len, 0);
    
    let mut result = Vec::new();
    
    // Process each 31-byte chunk
    for i in 0..num_chunks {
        let start = i * 31;
        let chunk = &bytes_padded[start..start + 31];
        
        // Convert chunk to field using little-endian (matches Noir's field_from_bytes)
        let mut field_value = BigUint::from(0u32);
        let mut offset = BigUint::from(1u32);
        
        for &byte in chunk {
            field_value += BigUint::from(byte) * &offset;
            offset *= 256u32;
        }
        
        result.push(field_value.to_string());
    }
    
    result
}

/// Normalize s value according to BIP-0062
fn normalize_s(s: &[u8]) -> Vec<u8> {
    let n = BigUint::from_bytes_be(&[
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xBC, 0xE6, 0xFA, 0xAD, 0xA7, 0x17, 0x9E, 0x84,
        0xF3, 0xB9, 0xCA, 0xC2, 0xFC, 0x63, 0x25, 0x51
    ]);
    let half_order = &n >> 1;
    
    let s_big = BigUint::from_bytes_be(s);
    if s_big > half_order {
        let new_s = &n - &s_big;
        let mut normalized_bytes = vec![0u8; 32];
        let s_bytes = new_s.to_bytes_be();
        normalized_bytes[32 - s_bytes.len()..].copy_from_slice(&s_bytes);
        normalized_bytes
    } else {
        s.to_vec()
    }
}

/// Convert BigUint to array of 6 chunks of 43 bits each
fn bigint_to_chunks(x: BigUint) -> Vec<String> {
    let modulus = 2u128.pow(43).to_biguint().unwrap();
    let mut chunks = Vec::new();
    let mut x_temp = x;
    
    for _ in 0..6 {
        let chunk = (&x_temp % &modulus).to_string();
        // No padding, just the raw number as a string
        chunks.push(chunk);
        x_temp = x_temp / &modulus;
    }
    
    chunks
}

/// Convert bytes to BigUint
fn bytes_to_bigint(bytes: &[u8]) -> BigUint {
    BigUint::from_bytes_be(bytes)
}

/// Generate Noir test case in TOML format with both byte arrays and Field values
fn generate_noir_toml(
    hashed_message: &[u8],
    pub_key_x: &[u8],
    pub_key_y: &[u8],
    signature: &[u8],
) -> String {
    // Generate Field values using pack_bytes (matches Noir's pack_bytes logic)
    let hashed_message_fields = pack_bytes(hashed_message);
    let pub_key_x_fields = pack_bytes(pub_key_x);
    let pub_key_y_fields = pack_bytes(pub_key_y);
    let signature_r_fields = pack_bytes(&signature[0..32]);
    let signature_s_fields = pack_bytes(&signature[32..64]);
    
    // Helper function to format field array for TOML
    let format_field_array = |fields: &Vec<String>| -> String {
        if fields.len() == 1 {
            format!("\"{}\"", fields[0])
        } else {
            let quoted_fields: Vec<String> = fields.iter().map(|f| format!("\"{}\"", f)).collect();
            format!("[{}]", quoted_fields.join(", "))
        }
    };
    
    format!(
        r#"# Field values (matching Noir's pack_bytes - 31-byte chunks)
hashed_message = {}
pub_key_x = {}
pub_key_y = {}
signature_r = {}
signature_s = {}
"#,
        format_field_array(&hashed_message_fields),
        format_field_array(&pub_key_x_fields),
        format_field_array(&pub_key_y_fields),
        format_field_array(&signature_r_fields),
        format_field_array(&signature_s_fields),
    )
}

/// Ensure a directory exists, creating it if necessary
fn ensure_directory_exists(dir_path: &Path) {
    if !dir_path.exists() {
        fs::create_dir_all(dir_path).expect("Failed to create directory");
    }
}

/// Delete a directory if it exists
fn delete_directory_if_exists(dir_path: &Path) {
    if dir_path.exists() {
        fs::remove_dir_all(dir_path).expect("Failed to delete directory");
        println!("Deleted existing directory: {}", dir_path.display());
    }
}

fn main() {
    let args = Args::parse();
    println!("Generating {} ECDSA test cases...", args.num_test_cases);

    // Create a simple message to hash (will be different for each test case)
    let message = b"Test message for signature";

    // Prepare output directories
    let snarkjs_tests_dir = Path::new("snarkjs").join("tests");
    let rapidsnark_tests_dir = Path::new("rapidsnark").join("tests");
    let noir_tests_dir = Path::new("noir").join("tests");

    // Clean existing directories
    for dir in [&snarkjs_tests_dir, &rapidsnark_tests_dir, &noir_tests_dir] {
        delete_directory_if_exists(dir);
        ensure_directory_exists(dir);
    }

    // Generate test cases
    for i in 0..args.num_test_cases {
        // Generate key pair
        let signing_key = SigningKey::random(&mut OsRng);
        let verifying_key = signing_key.verifying_key();
        
        // Hash the message with SHA256
        let mut hasher = Sha256::new();
        hasher.update(message);
        let message_hash = hasher.finalize().to_vec();
        
        // Sign the original message (not the hash)
        let signature: Signature = signing_key.sign(message);
        
        // Extract public key coordinates
        let pubkey_bytes = verifying_key.to_encoded_point(false);
        let pubkey_x = &pubkey_bytes.as_bytes()[1..33];
        let pubkey_y = &pubkey_bytes.as_bytes()[33..65];
        
        // Extract signature components
        let signature_bytes = signature.to_bytes();
        let (r, s) = signature_bytes.split_at(32);
        
        // Normalize s value according to BIP-0062
        let normalized_s = normalize_s(s);
        
        // Convert values to BigUint
        let r_bigint = bytes_to_bigint(r);
        let s_bigint = bytes_to_bigint(&normalized_s);
        let msghash_bigint = bytes_to_bigint(&message_hash);
        let pubkey_x_bigint = bytes_to_bigint(pubkey_x);
        let pubkey_y_bigint = bytes_to_bigint(pubkey_y);
        
        // Convert BigUints to chunks
        let r_chunks = bigint_to_chunks(r_bigint);
        let s_chunks = bigint_to_chunks(s_bigint);
        let msghash_chunks = bigint_to_chunks(msghash_bigint);
        let pubkey_x_chunks = bigint_to_chunks(pubkey_x_bigint);
        let pubkey_y_chunks = bigint_to_chunks(pubkey_y_bigint);
        
        // Create SnarkJS/Rapidsnark test case with chunked values
        let test_case = SnarkjsTestCase {
            r: r_chunks,
            s: s_chunks,
            msghash: msghash_chunks,
            pubkey: vec![
                pubkey_x_chunks,
                pubkey_y_chunks,
            ],
        };

        // Save SnarkJS/Rapidsnark test cases
        let json = serde_json::to_string_pretty(&test_case)
            .expect("Failed to serialize test case");
        
        // Verify the serialization format (uncomment for debugging)
        // println!("Serialized test case: {}", json);
        
        for dir in &[&snarkjs_tests_dir, &rapidsnark_tests_dir] {
            let file_path = dir.join(format!("test_case_{}.json", i + 1));
            fs::write(&file_path, &json)
                .expect("Failed to write test case file");
        }
        
        // Create and save Noir test case
        let noir_test = generate_noir_toml(
            &message_hash,
            pubkey_x,
            pubkey_y,
            &[r, &normalized_s].concat(),
        );
        
        let noir_file_path = noir_tests_dir.join(format!("test_case_{}.toml", i + 1));
        fs::write(&noir_file_path, noir_test)
            .expect("Failed to write Noir test case");
    }

    println!("Test cases generated successfully for SnarkJS, Rapidsnark, and Noir!");
    println!("Files are saved with 6 chunks of 43 bits each for snarkjs/rapidsnark.");

    // Print sample case details for verification
    if args.num_test_cases > 0 {
        println!("\nSample test case (index 0):");
        println!("Message: {}", String::from_utf8_lossy(message));
        println!("Message Hash: see generated files");
        println!("Public Key X and Y: see generated files");
        println!("Signature R and S: see generated files");
        println!("\nTest files have been written to:");
        println!("  - {} (6 chunks of 43 bits)", snarkjs_tests_dir.display());
        println!("  - {} (6 chunks of 43 bits)", rapidsnark_tests_dir.display());
        println!("  - {} (TOML format)", noir_tests_dir.display());
    }
}
