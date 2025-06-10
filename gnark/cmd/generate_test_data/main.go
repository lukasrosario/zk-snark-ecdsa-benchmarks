package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"strings"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark/backend/groth16"
)

type TestCase struct {
	R       string `json:"r"`
	S       string `json:"s"`
	MsgHash string `json:"msghash"`
	PubKeyX string `json:"pubkey_x"`
	PubKeyY string `json:"pubkey_y"`
}

func main() {
	if len(os.Args) < 4 {
		log.Fatal("Usage: go run main.go <test_case_num> <test_case_file> <proof_file>")
	}

	testCaseNum := os.Args[1]
	testCaseFile := os.Args[2] // This will be the full relative path from gas-bench
	proofFile := os.Args[3]    // This will be the full relative path from gas-bench

	// Load test case to get public inputs
	testCaseData, err := ioutil.ReadFile(testCaseFile)
	if err != nil {
		log.Fatal("Failed to read test case file:", err)
	}

	var testCase TestCase
	err = json.Unmarshal(testCaseData, &testCase)
	if err != nil {
		log.Fatal("Failed to parse test case:", err)
	}

	// Load proof
	proof := groth16.NewProof(ecc.BN254)
	f, err := os.Open(proofFile)
	if err != nil {
		log.Fatal("Failed to open proof file:", err)
	}
	defer f.Close()
	_, err = proof.ReadFrom(f)
	if err != nil {
		log.Fatal("Failed to read proof:", err)
	}

	// Generate Solidity test data
	solidityData := fmt.Sprintf(`        uint256[2] memory a = [uint256(0x%s), uint256(0x%s)];
        uint256[2][2] memory b = [[uint256(0x%s), uint256(0x%s)], [uint256(0x%s), uint256(0x%s)]];
        uint256[2] memory c = [uint256(0x%s), uint256(0x%s)];
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = uint256(%s);
        publicInputs[1] = uint256(%s);`,
		"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
		"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
		"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
		"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
		"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
		"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
		"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
		"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
		testCase.PubKeyX,
		testCase.PubKeyY,
	)

	// Read the test file template (adjust path since we're calling from gas-bench subdirectory)
	testFilePath := fmt.Sprintf("test/GasTest%s.t.sol", testCaseNum)
	content, err := ioutil.ReadFile(testFilePath)
	if err != nil {
		log.Fatal("Failed to read test file:", err)
	}

	// Replace placeholder with actual data
	placeholder := fmt.Sprintf("PROOF_DATA_PLACEHOLDER_%s", testCaseNum)
	updatedContent := strings.Replace(string(content), placeholder, solidityData, 1)

	// Write back the updated content
	err = ioutil.WriteFile(testFilePath, []byte(updatedContent), 0644)
	if err != nil {
		log.Fatal("Failed to write updated test file:", err)
	}

	log.Printf("✓ Test data generated for test case %s\n", testCaseNum)
}
