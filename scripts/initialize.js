const Aptos = require('aptos')
const {
    AptosClient,
    AptosAccount,
    FaucetClient,
    BCS,
    TxnBuilderTypes,
  } = Aptos;
  const getKey = require('./getKey')
  
  // devnet is used here for testing
  const NODE_URL = "https://fullnode.devnet.aptoslabs.com";
  const FAUCET_URL = "https://faucet.devnet.aptoslabs.com";
  
  const client = new AptosClient(NODE_URL);
  const faucetClient = new FaucetClient(NODE_URL, FAUCET_URL);
  
  let fs = require('fs')
  let path = require('path')
  let modulePath = "./liquidity_coin"
  let packageMetadata = fs.readFileSync(path.join(modulePath, "build", "CollectibleSwapLP", "package-metadata.bcs"));
  let moduleCode = fs.readFileSync(path.join(modulePath, "build", "CollectibleSwapLP", "bytecode_modules", "liquidity_coin.mv"));

  async function main() {
    // Generates key pair for Alice
    let key = getKey();
    let key_buffer = Buffer.from(key.replace("0x", ""), "hex")
    
    const alice = new AptosAccount(Uint8Array.from(key_buffer))
    console.log("alice", alice.address());
    // Creates Alice's account and mint 5000 test coins
    // await faucetClient.fundAccount(alice.address(), 5000);
  
    let resources = await client.getAccountResources(alice.address());
    let accountResource = resources.find(
      (r) => r.type === "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>"
    );
    console.log(
      `Alice coins: ${accountResource.data.coin.value}`
    );
  
    // // Generates key pair for Bob
    // const bob = new AptosAccount();
    // // Creates Bob's account and mint 0 test coins
    // await faucetClient.fundAccount(bob.address(), 0);
  
    // resources = await client.getAccountResources(bob.address());
    // accountResource = resources.find(
    //   (r) => r.type === "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>"
    // );
    // console.log(
    //   `Bob coins: ${(accountResource?.data as any).coin.value}. Should be 0!`
    // );
  
    // // We need to pass a token type to the `transfer` function.
    // const token = new TxnBuilderTypes.TypeTagStruct(
    //   TxnBuilderTypes.StructTag.fromString("0x1::aptos_coin::AptosCoin")
    // );
    
    packageMetadata = packageMetadata.toString('hex')
    packageMetadata = Uint8Array.from(Buffer.from(packageMetadata, "hex"))
    moduleCode = moduleCode.toString('hex')
    moduleCode = Uint8Array.from(Buffer.from(moduleCode, "hex"))

    const entryFunctionPayload =
      new TxnBuilderTypes.TransactionPayloadEntryFunction(
        TxnBuilderTypes.EntryFunction.natural(
          // Fully qualified module name, `AccountAddress::ModuleName`
          `${alice.address()}::pool`,
          // Module function
          "initialize_script",
          // The coin type to transfer
          [],
          // Arguments for function `transfer`: receiver account address and amount to transfer
          [
          ]
        )
      );
  
    // // Create a raw transaction out of the transaction payload
    const rawTxn = await client.generateRawTransaction(
      alice.address(),
      entryFunctionPayload
    );
  
    // // Sign the raw transaction with Alice's private key
    const bcsTxn = AptosClient.generateBCSTransaction(alice, rawTxn);
    // // Submit the transaction
    const transactionRes = await client.submitSignedBCSTransaction(bcsTxn);
  
    // // Wait for the transaction to finish
    await client.waitForTransaction(transactionRes.hash);
  
    // resources = await client.getAccountResources(bob.address());
    // accountResource = resources.find(
    //   (r) => r.type === "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>"
    // );
    // console.log(
    //   `Bob coins: ${(accountResource?.data as any).coin.value}. Should be 717!`
    // );
  
    process.exit(0);
  }
  
  main();
  