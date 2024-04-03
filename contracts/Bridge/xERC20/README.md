These contracts are pulled from https://github.com/defi-wonderland/xERC20

Commit: 77b2c6266ab07ae629517ad83ff058ad9e599a2b

The modifications being made are:

- Make contract upgradeable via OpenZeppelin's upgradeable contracts
- Instead of deploying full contracts, the factories will deploy OZ TransparentUpgradeableProxy
- Implementation addresses can be updated by the owner of the factories
- Add `OptimismMintableERC20` compatability (see [here](https://github.com/ethereum-optimism/optimism/blob/f54a2234f2f350795552011f35f704a3feb56a08/packages/contracts-bedrock/src/universal/IOptimismMintableERC20.sol)).