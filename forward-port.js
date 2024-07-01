const fs = require("fs");
const json5 = require("json5");
const file = process.argv[process.argv.length - 1]
const origData = fs.readFileSync(file,
    { encoding: 'utf8', flag: 'r' });

const data = json5.parse(origData)

data['runArgs'] = ["--network=host"]

fs.writeFileSync(file, JSON.stringify(data))
