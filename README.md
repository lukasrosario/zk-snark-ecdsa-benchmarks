# zk-SNARK ECDSA Benchmarks

This repository contains a benchmarking suite for ECDSA signature verification using zero-knowledge proofs (zk-SNARKs) with [snarkjs](https://github.com/iden3/snarkjs), [rapidsnark](https://github.com/iden3/rapidsnark), and [Noir](https://noir-lang.org/) implementations. It allows you to compare performance, proving time, and gas costs between these zk-SNARK implementations.

## Project Overview

zk-SNARKs enable proving knowledge of an ECDSA signature without revealing the signature itself. This is particularly useful for blockchain applications that require privacy-preserving identity verification. This benchmark suite:

1. Generates ECDSA signature test cases on the P-256 curve
2. Compiles Circom circuits for ECDSA verification
3. Performs trusted setup, witness computation, and proof generation
4. Measures proving time, verification time, and gas costs
5. Compares performance between snarkjs (JavaScript), rapidsnark (C++), and Noir implementations

## Prerequisites

- [Bun](https://bun.sh/) runtime for test case generation
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
- [Foundry](https://github.com/foundry-rs/foundry) - Ethereum development toolkit
- [Hyperfine](https://github.com/sharkdp/hyperfine) - Command-line benchmarking tool

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/zk-snark-ecdsa-benchmarks.git
   cd zk-snark-ecdsa-benchmarks
   ```

2. Install dependencies:
   ```bash
   bun install
   ```

## Generating Test Cases

The first step is to generate ECDSA signature test cases. This creates valid signature/public key pairs with the same message hash for testing both implementations:

```bash
bun run tests:generate --num-test-cases=10
```

This command:
1. Generates random ECDSA key pairs on the P-256 curve
2. Creates signatures for a random challenge message
3. Formats the signatures, public keys, and message hash into the required format for zk-SNARK circuits
4. Splits the values into 43-bit chunks (required by the circuit constraints)
5. Saves the test cases in the `snarkjs/tests`, `rapidsnark/tests`, and `noir/tests` directories

### Command line options:

- `--num-test-cases`: Number of test cases to generate (default: 10)

## Running Benchmarks

### NOTE: Go do docker -> Gear icon (settings) -> Resources -> Set Memory 16GB

You can run benchmarks for both implementations using Docker. This ensures a consistent environment and avoids dependency conflicts.

### SnarkJS Benchmarks

For **resumable execution** (recommended for long-running benchmarks):

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
  -v $(pwd)/rapidsnark/data:/out \
  --name zk-ecdsa-rapidsnark-benchmark \
  zk-ecdsa-rapidsnark
```

### Noir Benchmarks

```bash
cd noir
docker build -t zk-ecdsa-noir .
cd ..
docker run -v $(pwd)/tests:/app/tests -v $(pwd)/benchmarks:/app/benchmarks zk-ecdsa-noir
```

The Noir benchmarking process:
1. Installs Noir (nargo) and Barretenberg (bb) dependencies
2. Compiles the Noir ECDSA circuit and generates witnesses for each test case
3. Generates zk-SNARK proofs for each witness
4. Verifies the generated proofs

After running the benchmarks, results and artifacts will be available in the `noir/target` directory, organized by test case.

## Understanding Test Case Structure

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

## Benchmark Results

After running the benchmarks, you'll find the results in:

- `snarkjs/benchmarks/`: Contains proving time, verification time, and gas cost reports for snarkjs
- `rapidsnark/benchmarks/`: Contains proving time, verification time, and gas cost reports for rapidsnark
- `noir/target/`: Contains witness files, proofs, and verification keys for the Noir implementation

You can compare these results to determine which implementation performs better for your specific use case.

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
├── package.json                # Project dependencies
└── README.md                   # This file
```

## License

[MIT License](LICENSE)
