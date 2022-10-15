const Aptos = require('aptos')
const {
    AptosClient,
    AptosAccount,
    FaucetClient,
    BCS,
    TxnBuilderTypes,
  } = Aptos;
  const getMnemonics = require('./getMnemonics')
  
  let AptosWeb3 = require('@martiandao/aptos-web3.js')

  // devnet is used here for testing
  const NODE_URL = "https://fullnode.devnet.aptoslabs.com";
  const FAUCET_URL = "https://faucet.devnet.aptoslabs.com";
  
  const client = new AptosClient(NODE_URL);
  const faucetClient = new FaucetClient(NODE_URL, FAUCET_URL);
  
  let fs = require('fs')
  let path = require('path')

  let collectionName = "CloneX"
  let collectionDescription = "Faucet " + collectionName
  let collectionURL = "Fake URL " + collectionName
  async function main() {
    // Generates key pair for Alice
    let mnemonics = getMnemonics
    const wallet = new AptosWeb3.WalletClient(NODE_URL, FAUCET_URL)
    let aptosAccount = await wallet.getAccountFromMnemonic(mnemonics)
    let addr = aptosAccount.address()
    console.log("addr", aptosAccount.address());
    // Creates Alice's account and mint 5000 test coins
    // await faucetClient.fundAccount(alice.address(), 5000);
    let collection = null
    try {
        collection = await wallet.getCollection(addr, collectionName)
    } catch (e) {
        console.log("no collection")
    }
    if (!collection) {
        await wallet.createNFTCollection(mnemonics, collectionName, collectionDescription, collectionURL)
        console.log("collection created")
    } else {
        console.log("collection already exists")
    }
  
    process.exit(0);
  }

  async function createCollection(alice, name, description, url) {
    AptosWeb3.WalletClient()
    console.log("Creating collection", alice.address(), name, description, url)
    const entryFunctionPayload =
      new TxnBuilderTypes.TransactionPayloadEntryFunction(
        TxnBuilderTypes.EntryFunction.natural(
          // Fully qualified module name, `AccountAddress::ModuleName`
          `0x3::token`,
          // Module function
          "create_collection_script",
          // The coin type to transfer
          [],
          // Arguments for function `transfer`: receiver account address and amount to transfer
          [
            BCS.bcsSerializeStr(name),
            BCS.bcsSerializeStr(description),
            BCS.bcsSerializeStr(url),
            BCS.bcsSerializeUint64(1000000000),
            BCS.serializeVectorWithFunc([false, false, false], "serializeBool")
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

    console.log('done create collection')
  }
  
  main();
  