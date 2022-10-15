let AptosWeb3 = require('@martiandao/aptos-web3.js')
const NODE_URL = "https://fullnode.devnet.aptoslabs.com";
const FAUCET_URL = "https://faucet.devnet.aptoslabs.com";
let walletClient = new AptosWeb3.WalletClient(NODE_URL, FAUCET_URL)
walletClient.getUninitializedAccount().then(e => {
    console.log(e)
    process.exit(0)
})