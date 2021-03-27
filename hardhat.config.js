require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-truffle5");

const { removeConsoleLog } = require("hardhat-preprocessor");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

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
  solidity: "0.6.12",
  preprocess: {
    eachLine: removeConsoleLog((bre) => true),
    // eachLine: hardhatProcess.removeConsoleLog((bre) => bre.network.name !== 'hardhat' && bre.network.name !== 'localhost')
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    },
    test: {
      url: 'http://127.0.0.1:7545'
    }
  },
  solc: {
    optimizer: { // Turning on compiler optimization that removes some local variables during compilation
      enabled: true,
      runs: 200
    }
  }
};

