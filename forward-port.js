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


function replaceNetworkToHostInDockerComposeFile(file) {
    const yaml = require('yaml');
    const content = fs.readFileSync(file, 'utf8');
    const doc = yaml.parse(content);

    if (doc.services) {
        for (const service of Object.values(doc.services)) {
            service.network_mode = 'host';
            delete service.networks;
        }
    }

    fs.writeFileSync(file, yaml.stringify(doc));
}

const file = process.argv[process.argv.length - 1]

if (file.endsWith("devcontainer.json")) {
    replaceNetworkToHostInDevcontainerFile(file)
} else if (file.endsWith("docker-compose.yml") || file.endsWith("docker-compose.yaml")) {
    replaceNetworkToHostInDockerComposeFile(file)
}
