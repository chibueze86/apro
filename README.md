# Decentralized Identity Smart Contract

## Overview
The **Decentralized Identity** smart contract provides a mechanism for users and companies to register their decentralized identities (DID) and undergo KYC (Know Your Customer) verification. The contract allows an entity to prove its identity in a trustless manner on the blockchain.

## Features
- **User Registration**: Allows users to register a decentralized identity (DID).
- **Company Registration**: Enables companies to register their names on the blockchain.
- **KYC Verification**: The contract owner can verify users' and companies' identities.
- **Read Identity Information**: Fetch identity details and KYC verification status.

## Smart Contract Details

### Constants
- `contract-owner`: Defines the contract owner who has the authority to verify KYC.
- Error Codes:
  - `err-unauthorized (u100)`: Access restricted to the contract owner.
  - `err-already-registered (u101)`: The user or company is already registered.
  - `err-not-registered (u102)`: The user or company is not registered.
  - `err-kyc-already-verified (u103)`: KYC verification is already completed.

### Data Structures
#### Data Maps
- `users`: Stores user identity details and KYC verification status.
  - Key: `principal` (user's blockchain address)
  - Value:
    - `did`: (string-ascii 64) Unique Decentralized Identifier.
    - `kyc-verified`: (bool) Indicates if the user has passed KYC verification.
- `companies`: Stores company information and KYC verification status.
  - Key: `principal` (company's blockchain address)
  - Value:
    - `name`: (string-ascii 64) Company name.
    - `kyc-verified`: (bool) Indicates if the company has passed KYC verification.

### Read-Only Functions
- `get-user-did(user)`: Returns the DID of a given user.
- `is-user-kyc-verified(user)`: Checks if a user is KYC verified.
- `is-company-kyc-verified(company)`: Checks if a company is KYC verified.

### Public Functions
- `register-user(did)`: Allows a user to register a DID.
- `register-company(name)`: Enables a company to register its name.
- `verify-user-kyc(user)`: Allows the contract owner to verify a user's KYC.
- `verify-company-kyc(company)`: Allows the contract owner to verify a company's KYC.

### Private Functions
- `is-kyc-verified(entity)`: Checks if an entity (user or company) has passed KYC verification.

## Usage
1. **User/Company Registration**: Users and companies register by calling `register-user` or `register-company`.
2. **KYC Verification**: The contract owner verifies identities using `verify-user-kyc` or `verify-company-kyc`.
3. **Identity Retrieval**: Third parties can retrieve identity details using read-only functions.

## Security Considerations
- Only the contract owner can verify KYC to prevent unauthorized modifications.
- User and company registrations cannot be duplicated.
- Identity information is stored securely on the blockchain.