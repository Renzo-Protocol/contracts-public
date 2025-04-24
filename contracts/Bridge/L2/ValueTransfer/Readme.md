# Deployments

### On Arbitrum:

wstETH (LidoArbValueTransfer) will use the gateway router: 0x5288c571Fd7aD117beA99bF60FE0846C4E84F933

Native ETH (EthArbValueTransfer) will use ArbSys: 0x0000000000000000000000000000000000000064

### On Base:

wstETH (LidoOPValueTransfer) will use the lidoBridge: 0xac9D11cD4D7eF6e54F14643a393F68Ca014287AB

Native ETH (EthOPValueTransfer) will use the standard bridge: 0x4200000000000000000000000000000000000010

# OP Testnet

ETH Sepolia
stETH: https://sepolia.etherscan.io/address/0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af#writeProxyContract
wstETH: https://sepolia.etherscan.io/address/0xB82381A3fBD3FaFA77B3a7bE693342618240067b#writeContract
L1Bridge: https://sepolia.etherscan.io/address/0x4Abf633d9c0F4aEebB4C2E3213c7aa1b8505D332

OP Sepolia
wstETH: https://sepolia-optimism.etherscan.io/address/0x24B47cd3A74f1799b32B2de11073764Cb1bb318B#code
L2Bridge: https://sepolia-optimism.etherscan.io/address/0xdBA2760246f315203F8B716b3a7590F0FFdc704a

Test bridge TX on ETH Sepolia - L1 to L2 - Sent to L1LidoTokensBridge
https://sepolia.etherscan.io/tx/0x885714bf24acde1541658e6433ad3a9776a1ec3396bd87aadce6ef30c175cce6

Test bridge TX on OP Sepolia - L2 to L1 - Sent to L2ERC20ExtendedTokensBridge
https://sepolia-optimism.etherscan.io/tx/0x85d95d6bcc1942bffd4437b34fa0ea97a2a18e4ccecc9f4c8028ea567a43a448

Test Prove Message on OP - L1 - Sent to OptimismPortalProxy using SDK
https://sepolia.etherscan.io/tx/0x54a3137516d6e5882eeb851e764b7823d75f6506058c5328ffe69cc753f8ab0c

Test Finalize Tx on ETH Sepolia - L1 - Sent to OptimismPortal after 7 day delay


# Arbitrum

### Withdrawing ETH

Send withdraw request to arb_sys (precompile)
https://github.com/OffchainLabs/arb-os/blob/develop/contracts/arbos/builtin/ArbSys.sol
0x0000000000000000000000000000000000000064

Call withdrawEth()
https://github.com/OffchainLabs/arb-os/blob/develop/contracts/arbos/builtin/ArbSys.sol

   * Any time after the transaction's assertion is confirmed, funds can be transferred out of the bridge via the outbox contract

https://github.com/OffchainLabs/arbitrum-tutorials/blob/master/packages/outbox-execute/scripts/exec.js

Outbox on Mainnet
https://etherscan.io/address/0x0B9857ae2D4A3DBe74ffE1d7DF045bb7F96E4840

Test TX on Arb to bridge ETH back
https://arbiscan.io//tx/0x56d86c15749157ff813f0c553c4055d02d030aeb220e805aeb0546bc2dbb9eea

### Withdrawing Tokens

wstETH on Arb mainnet
https://arbiscan.io/address/0x5979D7b546E38E414F7E9822514be443A4800529

Call standard gateway router Outbound Transfer - it will get routed to Lido's custom gateway
https://arbiscan.io/address/0x5288c571Fd7aD117beA99bF60FE0846C4E84F933

Confirm the outbox the same way as ETH with the outbox

https://github.com/OffchainLabs/arbitrum-tutorials/blob/master/packages/token-withdraw/scripts/exec.js

Test TX on Arb to bridge wstETH to L1
https://arbiscan.io//tx/0xa9979e9958e26fe14462aff167a369707f8cd67e7314f2d570839fec2e14a045


### Arb Contract sweep test
ETH
https://arbiscan.io//tx/0x50208807aa19f1e1996678e08f62a09947b651238817a13807dbd6fe5fa986d4

wstETH
https://arbiscan.io//tx/0xc8592636fb0c215666529bcba84d8a6bd548ef1d62f62d9e78c61b9ecfca5ae3


# Example Transactions

Example L2 Withdraw
WithdrawTo: https://basescan.org/tx/0x79cb15a53800390ae333d45f9d9e7b1f9fde35c27a25b30fa0377096b7f3b53e#eventlog
Finalize: https://etherscan.io/tx/0x5c4b58750fd868904534dc4d854b482579e9aa7d0dfafa08fbd941cd1e0c9e4d

All data seem to be provided in the event associated with finalizing are emitted in MessagePassed() event on the withdraw on contract 0x4200000000000000000000000000000000000016.

If we decode the data payload we can store all messages that need to be indexed and finalized later.

