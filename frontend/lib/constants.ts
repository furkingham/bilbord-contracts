export const AD_EXCHANGE_ADDRESS = '0x0000000000000000000000000000000000000000';

export const MONAD_TESTNET_CHAIN_ID = '0x279F';
export const MONAD_TESTNET_RPC_URL = 'https://testnet.monad.com';
export const MONAD_TESTNET_CHAIN_PARAMS = {
  chainId: MONAD_TESTNET_CHAIN_ID,
  chainName: 'Monad Testnet',
  nativeCurrency: {
    name: 'Monad',
    symbol: 'MONAD',
    decimals: 18,
  },
  rpcUrls: [MONAD_TESTNET_RPC_URL],
  blockExplorerUrls: ['https://monad.com/explorer'],
};

// Değiştirilmesi gerekiyor: deploy edilen AdExchange kontrat adresini buraya yazın.
export const AD_EXCHANGE_ABI = [
  {
    "inputs": [
      { "internalType": "address", "name": "billboardId", "type": "address" },
      { "internalType": "uint256", "name": "crowdDensity", "type": "uint256" }
    ],
    "name": "triggerAuction",
    "outputs": [{ "internalType": "bytes32", "name": "auctionId", "type": "bytes32" }],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{ "internalType": "bytes32", "name": "auctionId", "type": "bytes32" }],
    "name": "resolveAuction",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{ "internalType": "bytes32", "name": "auctionId", "type": "bytes32" }],
    "name": "settlePayment",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{ "internalType": "bytes32", "name": "auctionId", "type": "bytes32" }, { "internalType": "uint256", "name": "bidAmount", "type": "uint256" }, { "internalType": "string", "name": "adURI", "type": "string" }],
    "name": "placeBid",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "crowdDensityThreshold",
    "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true, "internalType": "bytes32", "name": "auctionId", "type": "bytes32" },
      { "indexed": true, "internalType": "address", "name": "winner", "type": "address" },
      { "indexed": false, "internalType": "uint256", "name": "winningBid", "type": "uint256" },
      { "indexed": false, "internalType": "uint256", "name": "secondPrice", "type": "uint256" },
      { "indexed": false, "internalType": "uint256", "name": "timestamp", "type": "uint256" }
    ],
    "name": "AuctionFinalized",
    "type": "event"
  }
];
