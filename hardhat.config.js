require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
const path = require('path');

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  // This is a sample solc configuration that specifies which version of solc to use
  solidity: {
    version: "0.8.30",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  
  // Configure path mappings for external dependencies
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
    // Add path mappings for external dependencies
    root: "./",
  },
  
  // Network configuration
  networks: {
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: true,
      // Enable forking if needed
      // forking: {
      //   url: "https://eth-mainnet.alchemyapi.io/v2/YOUR-API-KEY",
      //   blockNumber: 14390000
      // }
    },
    // Other networks can be added here
  },
  
  // Gas reporter configuration
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  
  // Etherscan configuration for contract verification
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  
  // Typechain configuration
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
  
  // Path resolution for external dependencies
  // This helps Hardhat find the correct import paths
  paths: {
    sources: [
      "./contracts",
      "./contracts/lib"
    ],
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
    // Add node_modules to the path resolution
    root: "./"
  },
  // Configure external dependencies
  external: {
    contracts: [
      {
        artifacts: "node_modules/@tokenysolutions/t-rex/artifacts",
        deploy: "node_modules/@tokenysolutions/t-rex/deploy"
      },
      {
        artifacts: "node_modules/@onchain-id/solidity/artifacts"
      },
      {
        artifacts: "node_modules/@openzeppelin/contracts-upgradeable/artifacts"
      }
    ]
  }
};
