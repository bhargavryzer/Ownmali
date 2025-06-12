require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
const path = require('path');

module.exports = {
  // Configure path mappings for external dependencies
  paths: {
    sources: "./contracts",
    cache: "./cache",
    artifacts: "./artifacts",
    tests: "./test"
  },
  // Configure Solidity compiler
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: true
    }
  }
};
