import * as dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { ethers } from 'hardhat';

dotenv.config();

async function main() {
  const oracleAddress = process.env.ORACLE_ADDRESS;
  if (!oracleAddress) {
    throw new Error('ORACLE_ADDRESS environment variable is required');
  }

  const [deployer] = await ethers.getSigners();
  console.log('Deploying contracts with address:', deployer.address);

  const AdExchange = await ethers.getContractFactory('AdExchangeCore');
  const adExchange = await AdExchange.deploy(oracleAddress);
  await adExchange.waitForDeployment();

  console.log('AdExchangeCore deployed to:', adExchange.target);

  const output = {
    address: adExchange.target,
    network: 'monadTestnet',
    oracleAddress
  };

  const artifactDir = path.resolve(__dirname, '../frontend/lib');
  const artifactFile = path.join(artifactDir, 'deployedAddress.json');
  fs.writeFileSync(artifactFile, JSON.stringify(output, null, 2));
  console.log('Saved deployed address to frontend/lib/deployedAddress.json');

  console.log('Deployment completed. Copy the contract address into frontend/.env.local as NEXT_PUBLIC_AD_EXCHANGE_ADDRESS');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
