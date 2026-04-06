> Simple AMM (Automated Market Maker)
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