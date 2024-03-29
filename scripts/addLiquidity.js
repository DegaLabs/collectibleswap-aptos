let SDK = require('swap-aptos-sdk')
let mnemonics = require("./getMnemonics")
async function main() {
    let collectibleSwap = "0xd39111acba9f96a14150674b359d564e566f8057143a0593723fe753fc67c3b2"
    const NODE_URL = "https://fullnode.devnet.aptoslabs.com";
    const FAUCET_URL = "https://faucet.devnet.aptoslabs.com";
    let sdk = await SDK.createInstance(NODE_URL, FAUCET_URL, collectibleSwap)
    let aptosAccount = sdk.getAptosAccount({mnemonics: mnemonics})
    let aptosCoin = "0x1::aptos_coin::AptosCoin"
    await sdk.initializeTxBuilder(aptosAccount.address())
    let coinAmount = sdk.estimateLiquidityAddition(aptosCoin, "CloneX", "0xad73baea5ef67a1b52352ee2f781a132cfe6b9bdec544a5b55ef1b4557bfc5fd", 1)
    console.log('coinamoint', coinAmount)
    let txHash = await sdk.addLiquidity(
        aptosAccount,
        aptosCoin,
        "CloneX",
        ["15"],
        "0xad73baea5ef67a1b52352ee2f781a132cfe6b9bdec544a5b55ef1b4557bfc5fd",
        0,
        Math.round(coinAmount * 1050 / 1000)
    )
    
    console.log(txHash)
    process.exit(0)
}

main()