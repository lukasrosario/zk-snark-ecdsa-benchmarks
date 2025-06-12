package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"math/big"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"crypto/sha256"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark/backend"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/backend/witness"
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/frontend/cs/r1cs"
	"github.com/consensys/gnark/std/math/emulated"
)

// TestCase represents the structure of gnark test case JSON files
type TestCase struct {
	R       string `json:"r"`
	S       string `json:"s"`
	MsgHash string `json:"msghash"`
	PubKeyX string `json:"pubkey_x"`
	PubKeyY string `json:"pubkey_y"`
}

func main() {
	if len(os.Args) < 2 {
		log.Fatal("Usage: go run main.go circuit.go <command> [test_case.json]\nCommands: compile, prove, verify")
	}

	command := os.Args[1]

	switch command {
	case "compile":
		compileCircuit()
	case "prove":
		if len(os.Args) < 3 {
			// Batch mode - prove all test cases
			generateProofs()
		} else {
			// Single test case mode
			testCaseFile := os.Args[2]
			generateSingleProof(testCaseFile)
		}
	case "verify":
		if len(os.Args) < 3 {
			// Batch mode - verify all proofs
			verifyProofs()
		} else {
			// Single test case mode
			testCaseFile := os.Args[2]
			verifySingleProof(testCaseFile)
		}
	default:
		log.Fatal("Unknown command. Use: compile, prove, or verify")
	}
}

func compileCircuit() {
	fmt.Println("Compiling ECDSA circuit...")

	// Create circuit instance
	var circuit ECDSACircuit

	// Compile the circuit
	ccs, err := frontend.Compile(ecc.BN254.ScalarField(), r1cs.NewBuilder, &circuit)
	if err != nil {
		log.Fatal("Circuit compilation failed:", err)
	}

	fmt.Printf("Circuit compiled successfully. Constraints: %d\n", ccs.GetNbConstraints())

	// Setup phase
	fmt.Println("Running setup phase...")
	pk, vk, err := groth16.Setup(ccs)
	if err != nil {
		log.Fatal("Setup failed:", err)
	}

	// Save the compiled circuit and keys
	err = os.MkdirAll("data", 0755)
	if err != nil {
		log.Fatal("Failed to create data directory:", err)
	}

	// Save constraint system
	f, err := os.Create("data/circuit.r1cs")
	if err != nil {
		log.Fatal("Failed to create circuit file:", err)
	}
	defer f.Close()
	_, err = ccs.WriteTo(f)
	if err != nil {
		log.Fatal("Failed to write circuit:", err)
	}

	// Save proving key
	f, err = os.Create("data/proving.key")
	if err != nil {
		log.Fatal("Failed to create proving key file:", err)
	}
	defer f.Close()
	_, err = pk.WriteTo(f)
	if err != nil {
		log.Fatal("Failed to write proving key:", err)
	}

	// Save verifying key
	f, err = os.Create("data/verifying.key")
	if err != nil {
		log.Fatal("Failed to create verifying key file:", err)
	}
	defer f.Close()
	_, err = vk.WriteTo(f)
	if err != nil {
		log.Fatal("Failed to write verifying key:", err)
	}

	fmt.Println("Setup completed. Files saved to data/ directory.")
}

func generateProofs() {
	fmt.Println("Generating proofs for all test cases...")

	// Load constraint system
	ccs := groth16.NewCS(ecc.BN254)
	f, err := os.Open("data/circuit.r1cs")
	if err != nil {
		log.Fatal("Failed to open circuit file:", err)
	}
	defer f.Close()
	_, err = ccs.ReadFrom(f)
	if err != nil {
		log.Fatal("Failed to read circuit:", err)
	}

	// Load proving key
	pk := groth16.NewProvingKey(ecc.BN254)
	f, err = os.Open("data/proving.key")
	if err != nil {
		log.Fatal("Failed to open proving key file:", err)
	}
	defer f.Close()
	_, err = pk.ReadFrom(f)
	if err != nil {
		log.Fatal("Failed to read proving key:", err)
	}

	// Find all test case files
	testFiles, err := filepath.Glob("tests/test_case_*.json")
	if err != nil {
		log.Fatal("Failed to find test case files:", err)
	}

	if len(testFiles) == 0 {
		log.Fatal("No test case files found in tests/ directory")
	}

	fmt.Printf("Found %d test cases\n", len(testFiles))

	// Process each test case
	for _, testFile := range testFiles {
		fmt.Printf("Processing %s...\n", testFile)

		// Load test case
		testCase, err := loadTestCase(testFile)
		if err != nil {
			log.Printf("Failed to load test case %s: %v", testFile, err)
			continue
		}

		// Create witness
		witness, err := createWitness(testCase)
		if err != nil {
			log.Printf("Failed to create witness for %s: %v", testFile, err)
			continue
		}

		// Generate proof
		start := time.Now()
		proof, err := groth16.Prove(ccs, pk, witness, backend.WithProverHashToFieldFunction(sha256.New()))
		provingTime := time.Since(start)

		if err != nil {
			log.Printf("Failed to generate proof for %s: %v", testFile, err)
			continue
		}

		// Save proof
		baseName := filepath.Base(testFile)
		baseName = baseName[:len(baseName)-5] // Remove .json extension
		proofFile := filepath.Join("data", baseName+".proof")

		f, err := os.Create(proofFile)
		if err != nil {
			log.Printf("Failed to create proof file %s: %v", proofFile, err)
			continue
		}
		_, err = proof.WriteTo(f)
		f.Close()
		if err != nil {
			log.Printf("Failed to write proof to %s: %v", proofFile, err)
			continue
		}

		fmt.Printf("✓ Proof generated for %s in %v\n", baseName, provingTime)
	}

	fmt.Println("Proof generation completed.")
}

func verifyProofs() {
	fmt.Println("Verifying all generated proofs...")

	// Load verifying key
	vk := groth16.NewVerifyingKey(ecc.BN254)
	f, err := os.Open("data/verifying.key")
	if err != nil {
		log.Fatal("Failed to open verifying key file:", err)
	}
	defer f.Close()
	_, err = vk.ReadFrom(f)
	if err != nil {
		log.Fatal("Failed to read verifying key:", err)
	}

	// Find all proof files
	proofFiles, err := filepath.Glob("data/test_case_*.proof")
	if err != nil {
		log.Fatal("Failed to find proof files:", err)
	}

	if len(proofFiles) == 0 {
		log.Fatal("No proof files found in data/ directory")
	}

	fmt.Printf("Found %d proofs to verify\n", len(proofFiles))

	successCount := 0

	// Verify each proof
	for _, proofFile := range proofFiles {
		baseName := filepath.Base(proofFile)
		baseName = baseName[:len(baseName)-6] // Remove .proof extension
		testFile := filepath.Join("tests", baseName+".json")

		fmt.Printf("Verifying %s...\n", baseName)

		// Load test case
		testCase, err := loadTestCase(testFile)
		if err != nil {
			log.Printf("Failed to load test case %s: %v", testFile, err)
			continue
		}

		// Create public witness
		publicWitness, err := createPublicWitness(testCase)
		if err != nil {
			log.Printf("Failed to create public witness for %s: %v", baseName, err)
			continue
		}

		// Load proof
		proof := groth16.NewProof(ecc.BN254)
		f, err := os.Open(proofFile)
		if err != nil {
			log.Printf("Failed to open proof file %s: %v", proofFile, err)
			continue
		}
		_, err = proof.ReadFrom(f)
		f.Close()
		if err != nil {
			log.Printf("Failed to read proof from %s: %v", proofFile, err)
			continue
		}

		// Verify proof
		start := time.Now()
		err = groth16.Verify(proof, vk, publicWitness, backend.WithVerifierHashToFieldFunction(sha256.New()))
		verifyTime := time.Since(start)

		if err != nil {
			log.Printf("✗ Verification failed for %s: %v", baseName, err)
			continue
		}

		fmt.Printf("✓ Proof verified for %s in %v\n", baseName, verifyTime)
		successCount++
	}

	fmt.Printf("Verification completed. %d/%d proofs verified successfully.\n", successCount, len(proofFiles))
}

func loadTestCase(filename string) (*TestCase, error) {
	data, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	var testCase TestCase
	err = json.Unmarshal(data, &testCase)
	if err != nil {
		return nil, err
	}

	return &testCase, nil
}

func createWitness(testCase *TestCase) (witness.Witness, error) {
	// Parse hex strings to big integers
	r, err := parseHexToBigInt(testCase.R)
	if err != nil {
		return nil, fmt.Errorf("failed to parse R: %v", err)
	}

	s, err := parseHexToBigInt(testCase.S)
	if err != nil {
		return nil, fmt.Errorf("failed to parse S: %v", err)
	}

	msgHash, err := parseHexToBigInt(testCase.MsgHash)
	if err != nil {
		return nil, fmt.Errorf("failed to parse message hash: %v", err)
	}

	pubKeyX, err := parseHexToBigInt(testCase.PubKeyX)
	if err != nil {
		return nil, fmt.Errorf("failed to parse public key X: %v", err)
	}

	pubKeyY, err := parseHexToBigInt(testCase.PubKeyY)
	if err != nil {
		return nil, fmt.Errorf("failed to parse public key Y: %v", err)
	}

	// Create circuit assignment with emulated field elements
	assignment := ECDSACircuit{
		R:       emulated.ValueOf[emulated.P256Fr](r),
		S:       emulated.ValueOf[emulated.P256Fr](s),
		MsgHash: emulated.ValueOf[emulated.P256Fr](msgHash),
		PubKeyX: emulated.ValueOf[emulated.P256Fp](pubKeyX),
		PubKeyY: emulated.ValueOf[emulated.P256Fp](pubKeyY),
	}

	// Create witness
	witness, err := frontend.NewWitness(&assignment, ecc.BN254.ScalarField())
	if err != nil {
		return nil, err
	}

	return witness, nil
}

func createPublicWitness(testCase *TestCase) (witness.Witness, error) {
	witness, err := createWitness(testCase)
	if err != nil {
		return nil, err
	}

	publicWitness, err := witness.Public()
	if err != nil {
		return nil, err
	}

	return publicWitness, nil
}

func parseHexToBigInt(hexStr string) (*big.Int, error) {
	// Remove "0x" prefix if present
	hexStr = strings.TrimPrefix(hexStr, "0x")

	// Parse hex string to big.Int
	bigInt := new(big.Int)
	bigInt, ok := bigInt.SetString(hexStr, 16)
	if !ok {
		return nil, fmt.Errorf("invalid hex string: %s", hexStr)
	}

	return bigInt, nil
}

func generateSingleProof(testCaseFile string) {
	// Load constraint system
	ccs := groth16.NewCS(ecc.BN254)
	f, err := os.Open("data/circuit.r1cs")
	if err != nil {
		log.Fatal("Failed to open circuit file:", err)
	}
	defer f.Close()
	_, err = ccs.ReadFrom(f)
	if err != nil {
		log.Fatal("Failed to read circuit:", err)
	}

	// Load proving key
	pk := groth16.NewProvingKey(ecc.BN254)
	f, err = os.Open("data/proving.key")
	if err != nil {
		log.Fatal("Failed to open proving key file:", err)
	}
	defer f.Close()
	_, err = pk.ReadFrom(f)
	if err != nil {
		log.Fatal("Failed to read proving key:", err)
	}

	// Load test case
	testCase, err := loadTestCase(testCaseFile)
	if err != nil {
		log.Fatal("Failed to load test case:", err)
	}

	// Create witness
	witness, err := createWitness(testCase)
	if err != nil {
		log.Fatal("Failed to create witness:", err)
	}

	// Generate proof
	proof, err := groth16.Prove(ccs, pk, witness, backend.WithProverHashToFieldFunction(sha256.New()))
	if err != nil {
		log.Fatal("Failed to generate proof:", err)
	}

	// Extract test case number from filename
	baseName := filepath.Base(testCaseFile)
	testCaseNum := ""
	if match := regexp.MustCompile(`test_case_(\d+)\.json`).FindStringSubmatch(baseName); match != nil {
		testCaseNum = match[1]
	} else {
		log.Fatal("Invalid test case filename format")
	}

	// Save proof
	proofFile := filepath.Join("data", "proof_"+testCaseNum+".groth16")
	f, err = os.Create(proofFile)
	if err != nil {
		log.Fatal("Failed to create proof file:", err)
	}
	defer f.Close()
	_, err = proof.WriteTo(f)
	if err != nil {
		log.Fatal("Failed to write proof:", err)
	}

	fmt.Printf("✓ Proof generated for test case %s\n", testCaseNum)
}

func verifySingleProof(testCaseFile string) {
	// Load verifying key
	vk := groth16.NewVerifyingKey(ecc.BN254)
	f, err := os.Open("data/verifying.key")
	if err != nil {
		log.Fatal("Failed to open verifying key file:", err)
	}
	defer f.Close()
	_, err = vk.ReadFrom(f)
	if err != nil {
		log.Fatal("Failed to read verifying key:", err)
	}

	// Extract test case number from filename
	baseName := filepath.Base(testCaseFile)
	testCaseNum := ""
	if match := regexp.MustCompile(`test_case_(\d+)\.json`).FindStringSubmatch(baseName); match != nil {
		testCaseNum = match[1]
	} else {
		log.Fatal("Invalid test case filename format")
	}

	// Load test case for public witness
	testCase, err := loadTestCase(testCaseFile)
	if err != nil {
		log.Fatal("Failed to load test case:", err)
	}

	// Create public witness
	publicWitness, err := createPublicWitness(testCase)
	if err != nil {
		log.Fatal("Failed to create public witness:", err)
	}

	// Load proof
	proofFile := filepath.Join("data", "proof_"+testCaseNum+".groth16")
	proof := groth16.NewProof(ecc.BN254)
	f, err = os.Open(proofFile)
	if err != nil {
		log.Fatal("Failed to open proof file:", err)
	}
	defer f.Close()
	_, err = proof.ReadFrom(f)
	if err != nil {
		log.Fatal("Failed to read proof:", err)
	}

	// Verify proof
	err = groth16.Verify(proof, vk, publicWitness, backend.WithVerifierHashToFieldFunction(sha256.New()))
	if err != nil {
		log.Fatal("Proof verification failed:", err)
	}

	fmt.Printf("✓ Proof verified for test case %s\n", testCaseNum)
}
