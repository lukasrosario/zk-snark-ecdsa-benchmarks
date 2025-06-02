use clap::Parser;
use p256::ecdsa::{SigningKey, Signature, signature::Signer};
use rand::rngs::OsRng;
use serde::Serialize;
use std::fs;
use std::path::Path;
use num_bigint::BigUint;
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
    r: Vec<u8>,
    s: Vec<u8>,
    msghash: Vec<u8>,
    pubkey: Vec<Vec<u8>>,
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

/// Format bytes for Noir TOML format
fn format_bytes_for_toml(bytes: &[u8]) -> String {
    bytes.iter()
        .map(|b| b.to_string())
        .collect::<Vec<String>>()
        .join(",\n    ")
}

/// Generate Noir test case in TOML format
fn generate_noir_toml(
    hashed_message: &[u8],
    pub_key_x: &[u8],
    pub_key_y: &[u8],
    signature: &[u8],
) -> String {
    format!(
        r#"hashed_message = [
    {}
]
pub_key_x = [
    {}
]
pub_key_y = [
    {}
]
signature = [
    {}
]"#,
        format_bytes_for_toml(hashed_message),
        format_bytes_for_toml(pub_key_x),
        format_bytes_for_toml(pub_key_y),
        format_bytes_for_toml(signature)
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
        
        // Create SnarkJS/Rapidsnark test case
        let test_case = SnarkjsTestCase {
            r: r.to_vec(),
            s: normalized_s.clone(),
            msghash: message_hash.clone(),
            pubkey: vec![
                pubkey_x.to_vec(),
                pubkey_y.to_vec(),
            ],
        };

        // Save SnarkJS/Rapidsnark test cases
        let json = serde_json::to_string_pretty(&test_case)
            .expect("Failed to serialize test case");
        
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

    // Print sample case details for verification
    if args.num_test_cases > 0 {
        println!("\nSample test case (index 0):");
        println!("Message: {}", String::from_utf8_lossy(message));
        println!("Message Hash: see generated files");
        println!("Public Key X and Y: see generated files");
        println!("Signature R and S: see generated files");
        println!("\nTest files have been written to:");
        println!("  - {}", snarkjs_tests_dir.display());
        println!("  - {}", rapidsnark_tests_dir.display());
        println!("  - {}", noir_tests_dir.display());
    }
}
