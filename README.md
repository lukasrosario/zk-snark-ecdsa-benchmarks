# zk-SNARK ECDSA Benchmarks

This repository contains a benchmarking suite for ECDSA signature verification using zero-knowledge proofs (zk-SNARKs) with [snarkjs](https://github.com/iden3/snarkjs), [rapidsnark](https://github.com/iden3/rapidsnark), [Noir](https://noir-lang.org/), and [gnark](https://github.com/Consensys/gnark) implementations. It allows you to compare performance, proving time, and gas costs between these zk-SNARK implementations.

## Project Overview

zk-SNARKs enable proving knowledge of an ECDSA signature without revealing the signature itself. This is particularly useful for blockchain applications that require privacy-preserving identity verification. This benchmark suite:

1. Generates ECDSA signature test cases on the P-256 curve
2. Compiles circuits for ECDSA verification (Circom for snarkjs/rapidsnark, Noir for Noir, Go for gnark)
3. Performs trusted setup, witness computation, and proof generation
4. Measures proving time, verification time, and gas costs
5. Compares performance between snarkjs (JavaScript), rapidsnark (C++), Noir, and gnark (Go) implementations

## Prerequisites

- [Rust & Cargo](https://doc.rust-lang.org/cargo/) for test case generation
- [Docker](https://www.docker.com/) for running the benchmarks in isolated environments (with 16GB memory allocated)
- Download powers of tau
```bash
   curl -L "https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_22.ptau" -o pot22_final.ptau
```

### Additional dependencies (installed automatically in Docker)

- [circom](https://github.com/iden3/circom) - circuit compiler
- [snarkjs](https://github.com/iden3/snarkjs) - JavaScript implementation of zk-SNARKs
- [rapidsnark](https://github.com/iden3/rapidsnark) - C++ implementation of zk-SNARKs
- [Noir v1.0.0-beta.4](https://noir-lang.org/) - Rust implementation of zk-SNARKs
- [gnark v0.12.0](https://github.com/Consensys/gnark) - Go implementation of zk-SNARKs
- [Foundry](https://github.com/foundry-rs/foundry) - Ethereum development toolkit
- [Hyperfine](https://github.com/sharkdp/hyperfine) - Command-line benchmarking tool

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/zk-snark-ecdsa-benchmarks.git
   cd zk-snark-ecdsa-benchmarks
   ```

## Generating Test Cases

The first step is to generate ECDSA signature test cases. This creates valid signature/public key pairs with the same message hash for testing all implementations:

```bash
cargo run --bin generate_test_cases -- --num-test-cases=10
```

This command:
1. Generates random ECDSA key pairs on the P-256 curve
2. Creates signatures for a random challenge message
3. Formats the signatures, public keys, and message hash into the required format for zk-SNARK circuits
4. For snarkjs/rapidsnark: Splits the values into 43-bit chunks (required by the circuit constraints)
5. For Noir: Saves as byte arrays in TOML format
6. For gnark: Saves as hex strings for native big integer handling
7. Saves the test cases in the respective `tests/` directories

### Command line options:

- `--num-test-cases`: Number of test cases to generate (default: 10)

## Running Benchmarks

### NOTE: Go do docker -> Gear icon (settings) -> Resources -> Set Memory 16GB

You can run benchmarks for all implementations using Docker. This ensures a consistent environment and avoids dependency conflicts.

### SnarkJS Benchmarks

```bash
cd snarkjs
# Create persistent directory for all outputs
mkdir -p data
docker build -t zk-ecdsa-snarkjs .
cd ..
docker run -v $(pwd)/pot22_final.ptau:/app/pot22_final.ptau \
  -v $(pwd)/snarkjs/data:/out \
  --name zk-ecdsa-snarkjs-benchmark \
  zk-ecdsa-snarkjs
```

### RapidSnark Benchmarks

```bash
cd rapidsnark
# Create persistent directory for all outputs
mkdir -p data

docker build -t zk-ecdsa-rapidsnark .
cd ..

docker run -v $(pwd)/pot22_final.ptau:/app/pot22_final.ptau \
  -v $(pwd)/rapidsnark/tests:/app/tests \
  -v $(pwd)/rapidsnark/data:/out \
  --name zk-ecdsa-rapidsnark-benchmark \
  zk-ecdsa-rapidsnark
```

### Noir Benchmarks


```bash
cd noir
mkdir -p data

docker build -t zk-ecdsa-noir .
cd ..

docker run -v $(pwd)/noir/tests:/app/tests \
  -v $(pwd)/noir/data:/out \
  --name zk-ecdsa-noir-benchmark \
  zk-ecdsa-noir
```

### gnark Benchmarks

```bash
cd gnark
# Create persistent directory for all outputs
mkdir -p data

docker build -t zk-ecdsa-gnark .
cd ..

docker run -v $(pwd)/gnark/tests:/app/tests \
  -v $(pwd)/gnark/data:/out \
  --name zk-ecdsa-gnark-benchmark \
  zk-ecdsa-gnark
```

The gnark benchmarking process:
1. Compiles the gnark ECDSA circuit using Go and the gnark library
2. Runs the trusted setup phase (Groth16)
3. Generates zk-SNARK proofs for each test case
4. Verifies the generated proofs
5. Measures compilation, proving, and verification times

## Understanding Test Case Structure

### SnarkJS/RapidSnark Format
Each test case includes:

- **r and s components**: The two parts of an ECDSA signature, each split into 6 chunks of 43 bits
- **msghash**: The message hash that was signed, also split into 6 chunks of 43 bits
- **pubkey**: The public key coordinates (x, y), each split into 6 chunks of 43 bits

The splitting into 43-bit chunks is necessary to fit the values within the constraints of the zk-SNARK arithmetic circuits.

Example test case format:
```json
{
  "r": ["1234567890", "2345678901", "3456789012", "4567890123", "5678901234", "6789012345"],
  "s": ["9876543210", "8765432109", "7654321098", "6543210987", "5432109876", "4321098765"],
  "msghash": ["1111111111", "2222222222", "3333333333", "4444444444", "5555555555", "6666666666"],
  "pubkey": [
    ["1357924680", "2468013579", "3579124680", "4680235791", "5791346802", "6802457913"],
    ["9753186420", "8642097531", "7531086420", "6420975309", "5309864208", "4208753197"]
  ]
}
```

### gnark Format
gnark uses native big integer handling, so test cases use hex strings:

```json
{
  "r": "0x7ff59f2af286a36d4326786c48ab6f3cf35b67a382d23a5fbe59579a6c4dc",
  "s": "0x5591f7d661dc8232a010794b8283ed1b991fef9d96192b93b2",
  "msghash": "0x64ec88ca00b268e5ba1a35678a1b5316d212f4f366b2477232534a8eca37f3c",
  "pubkey_x": "0xd714c5b7fb8456a9ff2356f615de225cbfacbfa1a3cc248d1e1d193e0b33f90a",
  "pubkey_y": "0xa852b152ee3c2cd61aab12a3ee75e5924e8fa60e138c94964e4abbf7bc6c1097"
}
```

## Benchmark Results

After running the benchmarks, you'll find the results in:

- `snarkjs/data/`: Contains proving time, verification time, and gas cost reports for snarkjs (resumable execution)
- `rapidsnark/benchmarks/`: Contains proving time, verification time, and gas cost reports for rapidsnark  
- `noir/data/`: Contains compilation, witness, proof, verification, and gas usage artifacts for Noir (resumable execution)
- `gnark/data/`: Contains circuit files, proofs, and benchmark timing reports for gnark

### Circuit Compatibility

All three implementations now use **matching public input structures** for fair comparison:

**Public Inputs (visible to verifier):**
- **Message hash**: The hash of the message that was signed
- **Public key**: The signer's public key (x, y coordinates)  
- **Signature**: The ECDSA signature components (r, s)

This allows proving that a given signature is valid for the specified message hash and public key, making the benchmark results directly comparable between snarkjs, rapidsnark, and Noir implementations.

## Project Structure

```
zk-snark-ecdsa-benchmarks/
├── scripts/
│   └── generateTestCases.ts    # Test case generation script
├── snarkjs/                    # SnarkJS implementation
│   ├── circuit.circom          # Circuit implementation
│   ├── Dockerfile              # Docker setup for snarkjs
│   ├── lib/                    # Dependencies and libraries
│   ├── scripts/                # Benchmark scripts
│   └── tests/                  # Generated test cases
├── rapidsnark/                 # RapidSnark implementation
│   ├── circuit.circom          # Same circuit implementation
│   ├── Dockerfile              # Docker setup for rapidsnark
│   ├── lib/                    # Dependencies and libraries
│   ├── scripts/                # Benchmark scripts
│   └── tests/                  # Generated test cases
├── noir/                       # Noir implementation
│   ├── src/main.nr             # Noir circuit implementation
│   ├── Nargo.toml              # Noir project configuration
│   ├── scripts/                # Benchmark scripts
│   └── tests/                  # Generated test cases
├── gnark/                      # gnark implementation
│   ├── circuit.go              # gnark circuit implementation
│   ├── main.go                 # Main benchmarking executable
│   ├── go.mod                  # Go module configuration
│   ├── Dockerfile              # Docker setup for gnark
│   ├── scripts/                # Benchmark scripts
│   └── tests/                  # Generated test cases
├── package.json                # Project dependencies
└── README.md                   # This file
```

## License

[MIT License](LICENSE)
