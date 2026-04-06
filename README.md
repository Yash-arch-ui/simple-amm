> Automated Market Maker

A minimal Uniswap V2–style Automated Market Maker built in Solidity using a Factory → Pair → Router architecture. Supports liquidity provision, swaps, and deterministic pair deployment using CREATE2.


Factory
  └── creates → Pair (Liquidity Pool)
                    ├── holds reserves
                    ├── executes swaps
                    └── mints LP tokens

Router
  ├── addLiquidity
  ├── removeLiquidity
  └── swap (single/multi-hop)

  🔥 Features
⚖️ Constant Product AMM (x * y = k)
🏭 CREATE2 deterministic pair deployment
💱 Token swaps (single + multi-hop ready)
💧 Add / Remove liquidity
🧪 Foundry-based testing
🔐 ERC20 approval flow

🧠 Overview

This project implements a decentralized exchange (DEX) core similar to Uniswap V2, enabling:

💱 Trustless token swaps
💧 Liquidity provision
🏭 Deterministic pool creation
⚖️ Constant product pricing
