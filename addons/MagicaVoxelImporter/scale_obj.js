#!/usr/bin/env node

const [filename, scaleFactor, outFilename] = process.argv.slice(2);

if (!filename) {
    usage();
    throw new Error('filename missing');
}
if (isNaN(parseFloat(scaleFactor))) {
    usage();
    throw new Error('scaleFactor is not a number');
}

const { readFileSync, writeFileSync } = require('fs');

main();


function main() {
    const objFile = readFileSync(filename, 'ascii').split('\n');
    for (let i = 0; i < objFile.length; ++i) {
        if (objFile[i].startsWith('v ')) {
            objFile[i] = objFile[i].split(' ').map((v, i) =>
                i == 0 ? v : (parseFloat(v) * scaleFactor).toFixed(5).replace(/\.?0+$/g, '')
            ).join(' ');
        }
    }
    if (outFilename == '-') {
        console.log(objFile.join('\n'));
    } else {
        writeFileSync(outFilename || filename, objFile.join('\n'), 'ascii');
    }
}


function usage() {
    console.error(`Usage: ${process.argv[1]} <filename> <scalefactor> [outfilename]`);
    console.error('    if outfilename is - then write to stdout');
}
