const fs = require("fs");

function replaceNetworkToHostInDevcontainerFile(file) {
    const json5 = require("json5");
    const origData = fs.readFileSync(file,
        { encoding: 'utf8', flag: 'r' });

    const data = json5.parse(origData)
    data.runArgs = data.runArgs || [];
    data.runArgs.push("--network=host")
    data.runArgs = Array.from(new Set(data.runArgs))

    fs.writeFileSync(file, JSON.stringify(data))
}


const file = process.argv[process.argv.length - 1]

replaceNetworkToHostInDevcontainerFile(file)
