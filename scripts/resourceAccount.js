const aptos = require("aptos");
const { SHA3 } = require('sha3');

let sender = "0x43417434fd869edee76cca2a4d2301e528a1551b1d719b75c350c3c97d15b8b9"
let seed = "liquidswap_account_seed"
let senderSerialized = aptos.BCS.bcsToBytes(aptos.TxnBuilderTypes.AccountAddress.fromHex(sender))
let seedSerialized = aptos.BCS.bcsSerializeStr(seed)
let joined = [...senderSerialized, ...seedSerialized]

const hash = new SHA3(256);

hash.update(Buffer.from(joined));

console.log(hash.digest('hex'))