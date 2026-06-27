'use client';

import { useEffect, useState } from 'react';
import { ethers } from 'ethers';
import {
  AD_EXCHANGE_ADDRESS,
  AD_EXCHANGE_ABI,
  MONAD_TESTNET_CHAIN_ID,
  MONAD_TESTNET_CHAIN_PARAMS,
} from '@/lib/constants';

export const dynamic = 'force-dynamic';

const formatAddress = (address: string) => `${address.slice(0, 6)}...${address.slice(-4)}`;

export default function DashboardPage() {
  const [account, setAccount] = useState<string | null>(null);
  const [connected, setConnected] = useState<boolean>(false);
  const [balance, setBalance] = useState<string>('0');
  const [provider, setProvider] = useState<ethers.BrowserProvider | null>(null);
  const [ethereum, setEthereum] = useState<any>(null);
  const [depositAmount, setDepositAmount] = useState<string>('0.01');
  const [adURI, setAdURI] = useState<string>('https://example.com/ad.jpg');
  const [maxBid, setMaxBid] = useState<string>('0.05');
  const [txStatus, setTxStatus] = useState<string>('');
  const [errorMessage, setErrorMessage] = useState<string>('');
  const [activityLog, setActivityLog] = useState<string[]>([]);
  const [selectedScenario, setSelectedScenario] = useState<string>('central');
  const [campaignStep, setCampaignStep] = useState<number>(1);
  const [scenarioId, setScenarioId] = useState<string | null>(null);

  const scenarios = [
    {
      id: 'central',
      label: 'Şehir Merkezi Billboardu',
      description: 'Şehrin en yoğun kavşağında yer alan billboard. Kalabalık, yoğunluk ve süre yüksek.',
      features: ['Kalabalık: Yüksek', 'Yoğunluk: Çok Yoğun', 'Süre: 20 dk boyunca sürekli'],
    },
    {
      id: 'mall',
      label: 'AVM Girişi Billboardu',
      description: 'Alışveriş bölgesindeki yoğun yaya trafiği için optimize edilmiş reklam alanı.',
      features: ['Kalabalık: Orta-Yüksek', 'Yoğunluk: Orta', 'Süre: 15 dk boyunca devamlı'],
    },
    {
      id: 'highway',
      label: 'Otoyol Kenarı Billboardu',
      description: 'Yol üzerindeki hızlı geçen sürücü trafiğine hitap eden geniş ekran yüzeyi.',
      features: ['Kalabalık: Dengeli', 'Yoğunluk: Orta', 'Süre: 10 dk boyunca tekrarlayan'],
    },
  ];

  const selectedBoard = scenarios.find((scenario) => scenario.id === selectedScenario) ?? scenarios[0];

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const params = new URLSearchParams(window.location.search);
    const queryScenario = params.get('scenario');
    if (queryScenario && scenarios.some((scenario) => scenario.id === queryScenario)) {
      setScenarioId(queryScenario);
      setSelectedScenario(queryScenario);
      addActivityLog(`Seçilen billboard senaryosu: ${queryScenario}`);
    }
  }, []);

  const addActivityLog = (message: string) => {
    const timestamp = new Date().toLocaleTimeString('tr-TR', { hour12: false });
    setActivityLog((prev) => [`${timestamp} - ${message}`, ...prev].slice(0, 10));
  };

  const ensureMonadTestnet = async (ethereumProvider: any) => {
    if (!ethereumProvider || typeof ethereumProvider.request !== 'function') {
      return false;
    }

    try {
      const chainId = await ethereumProvider.request({ method: 'eth_chainId' });
      if (chainId === MONAD_TESTNET_CHAIN_ID) {
        return true;
      }

      await ethereumProvider.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: MONAD_TESTNET_CHAIN_ID }],
      });
      return true;
    } catch (err: any) {
      const isUnknownChain = err?.code === 4902 || err?.data?.originalError?.code === 4902 || String(err?.message).includes('4902');
      if (isUnknownChain) {
        try {
          await ethereumProvider.request({
            method: 'wallet_addEthereumChain',
            params: [MONAD_TESTNET_CHAIN_PARAMS],
          });
          await ethereumProvider.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: MONAD_TESTNET_CHAIN_ID }],
          });
          return true;
        } catch (addErr) {
          console.error('Monad testnet eklenemedi:', addErr);
          return false;
        }
      }
      console.error("Monad testnet'e geçilemedi:", err);
      return false;
    }
  };

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const ethereumProvider = (window as any).ethereum;

    if (!ethereumProvider) {
      setErrorMessage('MetaMask bulunamadı. Lütfen tarayıcınıza MetaMask uzantısını yükleyin.');
      return;
    }

    setEthereum(ethereumProvider);
    const browserProvider = new ethers.BrowserProvider(ethereumProvider);
    setProvider(browserProvider);

    const updateConnection = async () => {
      try {
        const chainReady = await ensureMonadTestnet(ethereumProvider);
        if (!chainReady) {
          setConnected(false);
          setErrorMessage('Lütfen MetaMask üzerinde Monad testnet ağına geçiş yapın.');
          return;
        }

        const accounts = await ethereumProvider.request({ method: 'eth_accounts' });
        if (Array.isArray(accounts) && accounts.length > 0) {
          setAccount(accounts[0]);
          setErrorMessage('');
          addActivityLog('MetaMask hesabı otomatik olarak algılandı.');
          const signer = await browserProvider.getSigner();
          const balanceReady = await fetchBalance(signer);
          if (!balanceReady) {
            setConnected(false);
            setErrorMessage('Bakiye alınamadı. Lütfen tekrar bağlanın.');
          }
        } else {
          setConnected(false);
        }
      } catch (err) {
        setConnected(false);
        setErrorMessage('MetaMask durumunu kontrol ederken bir hata oluştu.');
      }
    };

    const handleAccountsChanged = (accounts: string[]) => {
      if (!Array.isArray(accounts) || accounts.length === 0) {
        setAccount(null);
        setConnected(false);
        setErrorMessage('MetaMask hesabınız bağlantıyı kesti.');
        addActivityLog('MetaMask hesabı bağlantıyı kesti.');
      } else {
        setAccount(accounts[0]);
        setConnected(true);
        setErrorMessage('');
        addActivityLog('MetaMask hesabı değiştirildi.');
      }
    };

    const handleChainChanged = () => {
      setErrorMessage('Ağ değişti. Lütfen yeniden bağlanmayı deneyin.');
      addActivityLog('Ağ değiştirildi.');
      setConnected(false);
    };

    const hasListeners = ethereumProvider && typeof ethereumProvider.on === 'function' && typeof ethereumProvider.removeListener === 'function';
    if (hasListeners) {
      ethereumProvider.on('accountsChanged', handleAccountsChanged);
      ethereumProvider.on('chainChanged', handleChainChanged);
    }

    void updateConnection();

    return () => {
      if (hasListeners) {
        ethereumProvider.removeListener('accountsChanged', handleAccountsChanged);
        ethereumProvider.removeListener('chainChanged', handleChainChanged);
      }
    };
  }, []);

  const connectWallet = async () => {
    const ethereumProvider = ethereum || (typeof window !== 'undefined' ? (window as any).ethereum : null);
    if (!ethereumProvider) {
      setErrorMessage('MetaMask sağlayıcısı bulunamadı.');
      return;
    }

    try {
      const isChainReady = await ensureMonadTestnet(ethereumProvider);
      if (!isChainReady) {
        setConnected(false);
        setTxStatus('Monad testnet ağına geçilemedi');
        setErrorMessage('MetaMask Singleton otomatik olarak Monad testnet ağına geçemedi.');
        return;
      }

      const accounts: string[] = ethereumProvider.request
        ? await ethereumProvider.request({ method: 'eth_requestAccounts' })
        : provider
        ? await provider.send('eth_requestAccounts', [])
        : [];

      if (!accounts || accounts.length === 0) {
        setConnected(false);
        setTxStatus('Cüzdan bağlanamadı');
        setErrorMessage('MetaMask bağlantısı reddedildi veya hesap seçilmedi.');
        addActivityLog('MetaMask bağlantısı reddedildi veya hesap seçilmedi.');
        return;
      }

      const browserProvider = provider || new ethers.BrowserProvider(ethereumProvider);
      setProvider(browserProvider);
      const signer = await browserProvider.getSigner();
      const address = await signer.getAddress();
      setAccount(address);
      setErrorMessage('');
      const balanceReady = await fetchBalance(signer);
      if (!balanceReady) {
        setConnected(false);
        setTxStatus('Bakiye alınamadı');
        setErrorMessage('Bakiye güncellenirken bir sorun oluştu.');
        return;
      }
      setConnected(true);
      setTxStatus('Cüzdan bağlandı');
      addActivityLog('MetaMask ile bağlantı sağlandı.');
    } catch (err) {
      console.error(err);
      setConnected(false);
      setTxStatus('Cüzdan bağlanamadı');
      setErrorMessage('MetaMask bağlantısı reddedildi veya hata oluştu.');
      addActivityLog('MetaMask bağlantısı reddedildi veya hata oluştu.');
    }
  };

  const fetchBalance = async (signer: ethers.Signer) => {
    if (!provider) {
      setConnected(false);
      return false;
    }
    try {
      const address = await signer.getAddress();
      const rawBalance = await provider.getBalance(address);
      setBalance(ethers.formatEther(rawBalance));
      return true;
    } catch (err) {
      console.error('Balance fetch error:', err);
      setBalance('0');
      setConnected(false);
      return false;
    }
  };

  useEffect(() => {
    if (!provider || !account) return;
    if (!ethers.isAddress(AD_EXCHANGE_ADDRESS) || AD_EXCHANGE_ADDRESS === '0x0000000000000000000000000000000000000000') return;

    const setupContractLogger = async () => {
      try {
        const signer = await provider.getSigner();
        const contract = new ethers.Contract(AD_EXCHANGE_ADDRESS, AD_EXCHANGE_ABI, signer);

        const handleAuctionFinalized = (
          auctionId: string,
          winner: string,
          winningBid: bigint,
          secondPrice: bigint,
          timestamp: bigint
        ) => {
          const message = `AuctionFinalized: ${auctionId.slice(0, 8)}... kazanan ${winner}, teklif ${ethers.formatEther(winningBid)} ETH`;
          addActivityLog(message);
        };

        contract.on('AuctionFinalized', handleAuctionFinalized);

        return () => {
          contract.off('AuctionFinalized', handleAuctionFinalized);
        };
      } catch (err) {
        console.error(err);
      }
    };

    const cleanupPromise = setupContractLogger();
    return () => {
      cleanupPromise.then((cleanup) => {
        if (typeof cleanup === 'function') cleanup();
      });
    };
  }, [provider, account]);

  const depositFunds = async () => {
    if (!provider || !account) {
      setErrorMessage('Önce MetaMask ile bağlanın.');
      return;
    }
    if (!ethers.isAddress(AD_EXCHANGE_ADDRESS) || AD_EXCHANGE_ADDRESS === '0x0000000000000000000000000000000000000000') {
      setErrorMessage('AdExchange adresi ayarlı değil. Lütfen doğru adresi constants.ts dosyasına ekleyin.');
      return;
    }
    try {
      const signer = await provider.getSigner();
      setErrorMessage('');
      setTxStatus('Deposit işlemi gönderiliyor...');
      const tx = await signer.sendTransaction({
        to: AD_EXCHANGE_ADDRESS,
        value: ethers.parseEther(depositAmount)
      });
      await tx.wait();
      setTxStatus('Deposit tamamlandı');
      addActivityLog(`Deposit gönderildi: ${depositAmount} ETH`);
      await fetchBalance(signer);
    } catch (err) {
      console.error(err);
      setTxStatus('Deposit başarısız');
      setErrorMessage('Deposit işleminde hata oluştu. Lütfen MetaMask onay ekranını kontrol edin.');
      addActivityLog('Deposit işleminde hata oluştu.');
    }
  };

  const submitAdSettings = async () => {
    if (!provider || !account) {
      setErrorMessage('Önce MetaMask ile bağlanın.');
      return;
    }
    if (!ethers.isAddress(AD_EXCHANGE_ADDRESS) || AD_EXCHANGE_ADDRESS === '0x0000000000000000000000000000000000000000') {
      setErrorMessage('AdExchange adresi ayarlı değil. Lütfen doğru adresi constants.ts dosyasına ekleyin.');
      return;
    }
    try {
      const signer = await provider.getSigner();
      setErrorMessage('');
      setTxStatus('Reklam ayarları kaydediliyor...');
      addActivityLog(`ETKİNLİK ${campaignStep} kaydedildi: ${selectedBoard.label} / ${adURI} / ${maxBid} ETH`);
      setTxStatus('Reklam ayarı kaydedildi: ' + adURI + ' / ' + maxBid + ' ETH');
      const nextStep = campaignStep + 1;
      setCampaignStep(nextStep);
      setAdURI('https://example.com/ad.jpg');
      setMaxBid('0.05');
      addActivityLog(`Yeni etkinliğe geçildi: Etkinlik ${nextStep}`);
    } catch (err) {
      console.error(err);
      setTxStatus('Reklam ayarı kaydedilemedi');
      setErrorMessage('Reklam ayarları sırasında hata oluştu.');
      addActivityLog('Reklam ayarları sırasında hata oluştu.');
    }
  };

  return (
    <main className="min-h-screen bg-slate-950 text-slate-50">
      <div className="mx-auto grid max-w-7xl gap-10 px-6 py-16 lg:grid-cols-[0.95fr_0.8fr]">
        <section className="rounded-[2.5rem] border border-slate-800 bg-slate-900/90 p-10 shadow-2xl shadow-black/30">
          <div className="mb-8 flex flex-col gap-6 rounded-3xl border border-cyan-500/20 bg-cyan-500/10 p-6 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <p className="text-sm uppercase tracking-[0.3em] text-cyan-200">Reklam Yöneticisi</p>
              <h1 className="mt-4 text-4xl font-black text-white">Billboard Marka Paneli</h1>
            </div>
            <div className="rounded-3xl bg-slate-950/80 px-4 py-3 text-right text-sm text-slate-200">
              <p className="uppercase tracking-[0.2em] text-slate-400">Bağlı Hesap</p>
              <p className="mt-2">{account ? formatAddress(account) : 'Henüz bağlanmadı'}</p>
            </div>
          </div>
          <div className="rounded-[2rem] border border-slate-800 bg-slate-950/95 p-6 text-slate-200">
            <p className="text-sm uppercase tracking-[0.25em] text-cyan-300">Seçilen Billboard</p>
            <h2 className="mt-3 text-2xl font-semibold text-white">{selectedBoard.label}</h2>
            <p className="mt-2 text-slate-400">{selectedBoard.description}</p>
            <div className="mt-4 space-y-2 text-sm text-cyan-200">
              {selectedBoard.features.map((feature) => (
                <p key={feature}>• {feature}</p>
              ))}
            </div>
            <p className="mt-4 text-sm text-slate-400">Etkinlik Adımı: {campaignStep}</p>
          </div>

          <div className="grid gap-8 lg:grid-cols-[1.2fr_0.8fr]">
            <div className="space-y-8">
              <article className="rounded-[2rem] border border-slate-800 bg-slate-950/95 p-6">
                <h2 className="text-2xl font-semibold text-white">Cüzdan</h2>
                <p className="mt-3 text-slate-400">MetaMask ile bağlanarak billboard tekliflerinizi ve fon transferlerinizi kontrol edin.</p>
                <div className="mt-6 flex flex-col gap-4 sm:flex-row sm:items-center">
                  <button onClick={connectWallet} className="rounded-2xl bg-cyan-500 px-6 py-3 font-semibold text-slate-950 transition hover:bg-cyan-400">
                    {account ? 'Cüzdan Güncelle' : 'MetaMask Bağla'}
                  </button>
                  <div className="space-y-1 text-sm text-slate-300">
                    <p>ETH Bakiyesi: {balance}</p>
                    <p>Durum: {connected ? 'Bağlandı' : 'MetaMask cüzdanını bağla'}</p>
                  </div>
                </div>
              </article>

              <article className="rounded-[2rem] border border-slate-800 bg-slate-950/95 p-6">
                <h2 className="text-2xl font-semibold text-white">Reklam İçeriği</h2>
                <p className="mt-3 text-slate-400">Panoda yayınlanacak reklam URL'sini ve maksimum teklifi buradan ayarlayın.</p>
                <form onSubmit={(e) => { e.preventDefault(); submitAdSettings(); }} className="mt-6 grid gap-4">
                  <input
                    type="text"
                    value={adURI}
                    onChange={(e) => setAdURI(e.target.value)}
                    className="rounded-2xl border border-slate-700 bg-slate-950 px-4 py-3 text-slate-50 outline-none focus:border-cyan-400"
                    placeholder="Reklam görseli veya içerik URL'si"
                  />
                  <input
                    type="text"
                    value={maxBid}
                    onChange={(e) => setMaxBid(e.target.value)}
                    className="rounded-2xl border border-slate-700 bg-slate-950 px-4 py-3 text-slate-50 outline-none focus:border-cyan-400"
                    placeholder="Maksimum teklif (ETH)"
                  />
                  <button type="submit" className="rounded-2xl bg-violet-500 px-6 py-3 font-semibold text-slate-950 hover:bg-violet-400 transition">
                    Teklifi Kaydet
                  </button>
                </form>
              </article>
            </div>

            <div className="space-y-8">
              <article className="rounded-[2rem] border border-slate-800 bg-slate-950/95 p-6">
                <h2 className="text-2xl font-semibold text-white">Fon Yükleme</h2>
                <p className="mt-3 text-slate-400">AdExchange için ETH yatırma işlemini buradan başlatın.</p>
                <div className="mt-6 grid gap-4">
                  <input
                    type="text"
                    value={depositAmount}
                    onChange={(e) => setDepositAmount(e.target.value)}
                    className="rounded-2xl border border-slate-700 bg-slate-950 px-4 py-3 text-slate-50 outline-none focus:border-cyan-400"
                    placeholder="ETH miktarı"
                  />
                  <button onClick={depositFunds} className="rounded-2xl bg-emerald-500 px-6 py-3 font-semibold text-slate-950 hover:bg-emerald-400 transition">
                    Fon Yükle
                  </button>
                </div>
              </article>

              <article className="rounded-[2rem] border border-slate-800 bg-slate-950/95 p-6">
                <h2 className="text-2xl font-semibold text-white">Durum</h2>
                <p className="mt-3 text-slate-400">En son işlem durumları ve kampanya güncellemeleri burada görünür.</p>
                <div className="mt-5 rounded-3xl border border-slate-800 bg-slate-900/90 p-5 text-slate-300">
                  <p>{txStatus || 'Henüz işlem yapılmadı.'}</p>
                </div>
              </article>
            </div>
          </div>
        </section>

        <aside className="rounded-[2.5rem] border border-slate-800 bg-slate-900/90 p-10 shadow-2xl shadow-black/20">
          <div className="space-y-6">
            <div className="rounded-[2rem] border border-violet-500/20 bg-violet-500/10 p-6">
              <p className="text-sm uppercase tracking-[0.3em] text-violet-200">Bilboard Önizleme</p>
              <h2 className="mt-4 text-3xl font-semibold text-white">Reklam Kartı</h2>
              <p className="mt-3 text-slate-400">Seçtiğiniz reklam içeriği panoda nasıl görüneceğini burada takip edin.</p>
            </div>

            <div className="rounded-[2rem] border border-slate-800 bg-slate-950/95 p-6">
              <h3 className="text-xl font-semibold text-white">Reklam Özeti</h3>
              <div className="mt-5 space-y-3 text-slate-300">
                <div className="rounded-2xl border border-slate-800 bg-slate-900/80 p-4">
                  <p className="text-sm text-slate-400">Reklam Adresi</p>
                  <p className="mt-2 text-sm text-slate-200 break-all">{adURI}</p>
                </div>
                <div className="rounded-2xl border border-slate-800 bg-slate-900/80 p-4">
                  <p className="text-sm text-slate-400">Maksimum Teklif</p>
                  <p className="mt-2 text-lg font-semibold text-white">{maxBid} ETH</p>
                </div>
                <div className="rounded-2xl border border-slate-800 bg-slate-900/80 p-4">
                  <p className="text-sm text-slate-400">Smart Contract</p>
                  <p className="mt-2 text-sm text-slate-200 break-all">{AD_EXCHANGE_ADDRESS}</p>
                </div>
              </div>
            </div>
          </div>
        </aside>
      </div>
    </main>
  );
}
