import * as dotenv from 'dotenv';
import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';

dotenv.config();

const MONAD_RPC_URL = process.env.MONAD_RPC_URL || '';
const ADMIN_PRIVATE_KEY = process.env.ADMIN_PRIVATE_KEY || '';
const CHAIN_ID = parseInt(process.env.CHAIN_ID || '10143', 10);

const config: HardhatUserConfig = {
  solidity: '0.8.20',
  networks: {
    hardhat: {
      chainId: 1337
    },
    monadTestnet: {
      url: MONAD_RPC_URL,
      chainId: CHAIN_ID,
      accounts: ADMIN_PRIVATE_KEY ? [ADMIN_PRIVATE_KEY] : []
    }
  }
};

export default config;
