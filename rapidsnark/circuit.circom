pragma circom 2.1.5;

include "./lib/circom-ecdsa-p256/circuits/ecdsa.circom";

component main { public [msghash] } = ECDSAVerifyNoPubkeyCheck(43, 6);