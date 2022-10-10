const aptos = require("aptos");
const { SHA3 } = require('sha3');

function toUTF8Array(str) {
    var utf8 = [];
    for (var i = 0; i < str.length; i++) {
        var charcode = str.charCodeAt(i);
        if (charcode < 0x80) utf8.push(charcode);
        else if (charcode < 0x800) {
            utf8.push(0xc0 | (charcode >> 6),
                0x80 | (charcode & 0x3f));
        }
        else if (charcode < 0xd800 || charcode >= 0xe000) {
            utf8.push(0xe0 | (charcode >> 12),
                0x80 | ((charcode >> 6) & 0x3f),
                0x80 | (charcode & 0x3f));
        }
        // surrogate pair
        else {
            i++;
            // UTF-16 encodes 0x10000-0x10FFFF by
            // subtracting 0x10000 and splitting the
            // 20 bits of 0x0-0xFFFFF into two halves
            charcode = 0x10000 + (((charcode & 0x3ff) << 10)
                | (str.charCodeAt(i) & 0x3ff));
            utf8.push(0xf0 | (charcode >> 18),
                0x80 | ((charcode >> 12) & 0x3f),
                0x80 | ((charcode >> 6) & 0x3f),
                0x80 | (charcode & 0x3f));
        }
    }
    return utf8;
}

let sender = "0x4da5a5e0dee5c0372b73b9863541bc5b475b0f8ebfd853772bc9c529967b782a"
let seed = "collectibleswap_resource_account_seed"
let senderSerialized = aptos.BCS.bcsToBytes(aptos.TxnBuilderTypes.AccountAddress.fromHex(sender))
console.log('senderSerialized', Buffer.from(senderSerialized).toString('hex'))
let seedSerialized = toUTF8Array(seed)
console.log('seedSerialized', Buffer.from(seedSerialized).toString('hex'))
let joined = [...senderSerialized, ...seedSerialized]
    ]

const hash = new SHA3(256);

let arr = [1, 1, 1234, 1]
let serializer = new aptos.BCS.Serializer()

serializer.serializeU32AsUleb128(arr.length);
arr.forEach((item) => {
    serializer.serializeU64(item)
});

// aptos.BCS.serializeVector < aptos.BCS.Uint64 > (arr, serializer)
console.log('s', serializer.getBytes(), Buffer.from(serializer.getBytes()).toString('hex'))

let deser = new aptos.BCS.Deserializer(serializer.getBytes())
deser.deserializeBytes()

hash.update(Buffer.from(joined));

console.log(hash.digest('hex'))