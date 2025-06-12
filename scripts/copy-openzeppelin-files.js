const fs = require('fs-extra');
const path = require('path');

// Source and destination paths
const srcPath = path.join(__dirname, '..', 'node_modules', '@openzeppelin');
const destPath = path.join(__dirname, '..', 'contracts', 'lib', '@openzeppelin');

// Ensure the destination directory exists
fs.ensureDirSync(destPath);

// Copy the OpenZeppelin contracts to the lib directory
console.log(`Copying OpenZeppelin contracts from ${srcPath} to ${destPath}...`);
fs.copySync(srcPath, destPath, { overwrite: true });

console.log('OpenZeppelin contracts copied successfully!');
