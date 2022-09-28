let fs = require('fs')
let path = require('path')
let modulePath = "./liquidity_coin"
const packageMetadata = fs.readFileSync(path.join(modulePath, "build", "CollectibleSwapLP", "package-metadata.bcs"));
const moduleData = fs.readFileSync(path.join(modulePath, "build", "CollectibleSwapLP", "bytecode_modules", "liquidity_coin.mv"));

console.log('packageMetadata', packageMetadata.toString('hex'))
console.log('moduleData', moduleData.toString('hex'))