# LSD & Omni Vault Contracts

## Project Description

This project implements a cross-chain Liquid Staking Derivatives (LSD) optimization system. It leverages OmniVault deployments across multiple chains, utilizing cross-chain communication protocols such as CCTP and Hyperlane for bridging and messaging capabilities. The primary goal is to optimize yield rates for LSD contracts by enabling seamless cross-chain operations and arbitrage opportunities.

## Technical Architecture

### Core Components

#### DeFi Protocol Integrations
- **Aave V3**
  - Used for lending operations
  - Reference: [Aave V3 Documentation](https://docs.aave.com/developers/)

- **Compound V3**
  - Utilized for additional lending markets
  - Enables cross-protocol yield optimization
  - Reference: [Compound V3 Documentation](https://docs.compound.finance/)


#### Cross-Chain Communication
- **CCTP (Cross-Chain Transfer Protocol)**
  - Used for secure and efficient cross-chain USDC transfers
  - Implements Circle's CCTP standard for stablecoin bridging
  - Reference: [Circle CCTP Documentation](https://developers.circle.com/stablecoins/cctp-getting-started)

- **Hyperlane**
  - Implements cross-chain messaging protocol
  - Enables secure message passing between chains
  - Reference: [Hyperlane Documentation](https://docs.hyperlane.xyz/)


### Dependencies

#### External Libraries
- `@openzeppelin/contracts@^5.2.0`
  - Used for standard security implementations
  - Includes ECDSA signature verification
  - Reference: [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts)

- `@openzeppelin/contracts-upgradeable@^5.2.0`
  - Implements upgradeable contract patterns
  - Used for EIP712 signature verification
  - Reference: [OpenZeppelin Upgradeable Contracts](https://docs.openzeppelin.com/upgrades-plugins)