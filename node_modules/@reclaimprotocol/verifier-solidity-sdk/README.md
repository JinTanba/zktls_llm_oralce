# @reclaimprotocol/verifier-solidity-sdk

A verifier-oriented version of Reclaim's Solidity SDK, designed to make deploying and verifying Reclaim contracts easier.

## Overview

`@reclaimprotocol/verifier-solidity-sdk` allows you to deploy a Reclaim contract that can be used to verify proofs in your Solidity smart contracts. This SDK is tailored specifically for verifiers who want to integrate Reclaim proof verification into their Ethereum or EVM-compatible smart contracts.

## Installation

Start using `@reclaimprotocol/verifier-solidity-sdk` in your project by running:

```bash
npm i @reclaimprotocol/verifier-solidity-sdk
```

## Usage

Below is an example of how to use the SDK to deploy a Reclaim contract and verify proofs:

```
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@reclaimprotocol/verifier-solidity-sdk/contracts/Reclaim.sol";
import "@reclaimprotocol/verifier-solidity-sdk/contracts/Addresses.sol";

contract Attestor {
   address public reclaimAddress;

   constructor() {
      // Replace with the network you are deploying on
      reclaimAddress = Addresses.PLOYGON_MUMBAI_TESTNET; 
   }

   function verifyProof(Reclaim.Proof memory proof) public view {
       Reclaim(reclaimAddress).verifyProof(proof);
       // Your business logic upon successful verification
       // Example: Verify that proof.context matches your expectations
   }
}
```

### Key Features

- **Verifier Oriented**: Tailored specifically for users who want to verify Reclaim proofs.
- **Easy Network Configuration**: Use predefined network addresses (e.g., `Addresses.ETHEREUM`).
- **Proof Verification**: Easily integrate Reclaim proof verification in your contracts.

### Addresses

The package includes a list of predefined addresses for different networks that you can use when deploying your contract. You can find these in `contracts/Addresses.sol` or preferably in [Reclaim Documentation](https://docs.reclaimprotocol.org/solidity/supported-networks)
