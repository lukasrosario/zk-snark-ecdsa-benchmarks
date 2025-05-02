import { Crypto } from "@peculiar/webcrypto";
import * as fs from 'fs';
import * as path from 'path';
import { Buffer } from 'node:buffer';

// Initialize WebCrypto
const crypto = new Crypto();

// Function to convert bigint to array of 6 chunks of 43 bits each
function bigintToChunks(x: bigint): bigint[] {
  const mod = 2n ** 43n;
  const ret: bigint[] = [];
  let xTemp = x;
  
  for (let i = 0; i < 6; i++) {
    ret.push(xTemp % mod);
    xTemp = xTemp / mod;
  }
  
  return ret;
}

// Function to convert Uint8Array to bigint
function uint8ArrayToBigint(arr: Uint8Array): bigint {
  let result = 0n;
  for (let i = 0; i < arr.length; i++) {
    result = result * 256n + BigInt(arr[i] as number);
  }
  return result;
}

// Function to generate a key pair
async function generateKeyPair(): Promise<{ privateKey: CryptoKey, publicKey: CryptoKey }> {
  return crypto.subtle.generateKey(
    {
      name: "ECDSA",
      namedCurve: "P-256"
    },
    true,
    ["sign", "verify"]
  ) as Promise<{ privateKey: CryptoKey, publicKey: CryptoKey }>;
}

// Function to sign a message with a private key
async function signMessage(
  privateKey: CryptoKey,
  message: Uint8Array
): Promise<Uint8Array> {
  const signatureBuffer = await crypto.subtle.sign(
    {
      name: "ECDSA",
      hash: "SHA-256"
    },
    privateKey,
    message
  );
  return new Uint8Array(signatureBuffer);
}

// Function to export a public key as raw bytes
async function exportPublicKey(publicKey: CryptoKey): Promise<Uint8Array> {
  const keyBuffer = await crypto.subtle.exportKey("raw", publicKey);
  return new Uint8Array(keyBuffer);
}

// Function to create a directory if it doesn't exist
function ensureDirectoryExists(dirPath: string): void {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

// Function to delete a directory if it exists
function deleteDirectoryIfExists(dirPath: string): void {
  if (fs.existsSync(dirPath)) {
    fs.rmSync(dirPath, { recursive: true, force: true });
    console.log(`Deleted existing directory: ${dirPath}`);
  }
}

// Define the test case type for better type safety
interface TestCase {
  index: number;
  challenge: Uint8Array;
  challengeBigint: bigint;
  challengeChunks: bigint[];
  pubkeyX: Uint8Array;
  pubkeyY: Uint8Array;
  pubkeyXBigint: bigint;
  pubkeyYBigint: bigint;
  pubkeyXChunks: bigint[];
  pubkeyYChunks: bigint[];
  signature: Uint8Array;
  r: Uint8Array;
  s: Uint8Array;
  rBigint: bigint;
  sBigint: bigint;
  rChunks: bigint[];
  sChunks: bigint[];
}

// Parse command line arguments
function parseArgs(): { numTestCases: number } {
  const args = process.argv.slice(2);
  let numTestCases = 10; // Default value
  
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--num-test-cases' || args[i] === '-n') {
      const value = parseInt(args[i + 1] ?? '10');
      if (!isNaN(value) && value > 0) {
        numTestCases = value;
      }
    }
  }
  
  return { numTestCases };
}

// Main function to generate test cases
async function generateTestCases(numTestCases: number) {
  console.log(`Generating ${numTestCases} ECDSA test cases...`);
  
  // Generate a random challenge
  const challenge = new Uint8Array(32);
  crypto.getRandomValues(challenge);
  const challengeBigint = uint8ArrayToBigint(challenge);
  const challengeChunks = bigintToChunks(challengeBigint);
  
  // Generate key pairs
  const keyPairs = await Promise.all(
    Array(numTestCases).fill(null).map(() => generateKeyPair())
  );
  
  // Generate signatures for each key pair
  const testCases: TestCase[] = [];
  for (const keyPair of keyPairs) {
    const signature = await signMessage(keyPair.privateKey, challenge);
    const publicKeyRaw = await exportPublicKey(keyPair.publicKey);
    
    // Split public key into x and y coordinates (first 32 bytes is x, next 32 bytes is y)
    const pubkeyX = publicKeyRaw.slice(1, 33);
    const pubkeyY = publicKeyRaw.slice(33, 65);
    
    // Convert to bigints
    const pubkeyXBigint = uint8ArrayToBigint(pubkeyX);
    const pubkeyYBigint = uint8ArrayToBigint(pubkeyY);
    
    // Split signature into r and s (first 32 bytes is r, next 32 bytes is s)
    const r = signature.slice(0, 32);
    const s = signature.slice(32, 64);
    
    // Convert to bigints
    const rBigint = uint8ArrayToBigint(r);
    const sBigint = uint8ArrayToBigint(s);
    
    // Convert to chunks
    const rChunks = bigintToChunks(rBigint);
    const sChunks = bigintToChunks(sBigint);
    const pubkeyXChunks = bigintToChunks(pubkeyXBigint);
    const pubkeyYChunks = bigintToChunks(pubkeyYBigint);
    
    testCases.push({
      index: testCases.length,
      challenge,
      challengeBigint,
      challengeChunks,
      pubkeyX,
      pubkeyY,
      pubkeyXBigint,
      pubkeyYBigint,
      pubkeyXChunks,
      pubkeyYChunks,
      signature,
      r,
      s,
      rBigint,
      sBigint,
      rChunks,
      sChunks
    });
  }
  
  // Delete existing tests directories if they exist
  const snarkjsTestsDirPath = path.join('snarkjs', 'tests');
  const rapidsnarkTestsDirPath = path.join('rapidsnark', 'tests');
  
  deleteDirectoryIfExists(snarkjsTestsDirPath);
  deleteDirectoryIfExists(rapidsnarkTestsDirPath);
  
  // Create directories for test cases
  ensureDirectoryExists(snarkjsTestsDirPath);
  ensureDirectoryExists(rapidsnarkTestsDirPath);
  
  // Generate and save individual test cases for snarkjs
  testCases.forEach((testCase, i) => {
    const snarkjsTestCase = {
      r: testCase.rChunks.map(chunk => chunk.toString()),
      s: testCase.sChunks.map(chunk => chunk.toString()),
      msghash: testCase.challengeChunks.map(chunk => chunk.toString()),
      pubkey: [
        testCase.pubkeyXChunks.map(chunk => chunk.toString()),
        testCase.pubkeyYChunks.map(chunk => chunk.toString())
      ]
    };
    
    // Save to snarkjs directory
    fs.writeFileSync(
      path.join('snarkjs', 'tests', `test_case_${i+1}.json`),
      JSON.stringify(snarkjsTestCase, null, 2)
    );
    
    // Save to rapidsnark directory
    fs.writeFileSync(
      path.join('rapidsnark', 'tests', `test_case_${i+1}.json`),
      JSON.stringify(snarkjsTestCase, null, 2)
    );
  });
  
  console.log("Test cases generated successfully for both snarkjs and rapidsnark!");
  
  // Print a sample test case for verification
  const sampleCase = testCases[0];
  if (sampleCase) {
    console.log("\nSample test case (index 0):");
    console.log("Challenge:", Buffer.from(sampleCase.challenge).toString('hex'));
    console.log("Public Key X:", sampleCase.pubkeyXBigint.toString());
    console.log("Public Key Y:", sampleCase.pubkeyYBigint.toString());
    console.log("Signature R:", sampleCase.rBigint.toString());
    console.log("Signature S:", sampleCase.sBigint.toString());
  }
}

// Parse arguments and run the main function
const { numTestCases } = parseArgs();
generateTestCases(numTestCases).catch(console.error);

