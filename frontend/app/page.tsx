'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';

const scenarios = [
  {
    id: 'central',
    label: 'Şehir Merkezi Billboardu',
    subtitle: 'Ana Kavşak',
    description: 'Şehrin en yoğun bölgesinde, gün boyu kalabalığın yoğun olduğu reklam yüzeyi.',
    features: ['Kalabalık: Yüksek', 'Yoğunluk: Çok Yoğun', 'Süre: 20 dk boyunca sürekli'],
  },
  {
    id: 'mall',
    label: 'AVM Girişi Billboardu',
    subtitle: 'Alışveriş Bölgesi',
    description: 'Kalabalık alışveriş trafiği ve uzun bekleme alanları ile ideal marka görünürlüğü sunar.',
    features: ['Kalabalık: Orta-Yüksek', 'Yoğunluk: Orta', 'Süre: 15 dk boyunca devamlı'],
  },
  {
    id: 'highway',
    label: 'Otoyol Kenarı Billboardu',
    subtitle: 'Hızlı Geçiş',
    description: 'Yüksek hızda geçen sürücülerin ve yolcu trafiğinin önünde kalan dikkat çekici reklam alanı.',
    features: ['Kalabalık: Dengeli', 'Yoğunluk: Orta', 'Süre: 10 dk boyunca tekrarlayan'],
  },
];

export default function HomePage() {
  const [selectedScenario, setSelectedScenario] = useState('central');
  const router = useRouter();
  const selected = scenarios.find((scenario) => scenario.id === selectedScenario);

  const goToDashboard = (scenarioId: string) => {
    setSelectedScenario(scenarioId);
    router.push(`/dashboard?scenario=${scenarioId}`);
  };

  return (
    <main className="min-h-screen bg-slate-950 text-slate-50">
      <div className="mx-auto flex min-h-screen max-w-6xl flex-col justify-center gap-12 px-6 py-16">
        <section className="rounded-[2.5rem] border border-slate-800 bg-slate-900/90 p-12 shadow-2xl shadow-black/40 backdrop-blur-xl">
          <div className="mb-10 space-y-5">
            <span className="inline-flex rounded-full border border-cyan-500/25 bg-cyan-500/10 px-4 py-1 text-sm uppercase tracking-[0.3em] text-cyan-300">
              Müşteri Girişi</span>
            <h1 className="text-5xl font-black tracking-tight text-white">Billboard Kampanya Seçimi</h1>
            <p className="max-w-3xl text-xl leading-8 text-slate-400">
              Müşteri artık giriş ekranında üç farklı reel reklam senaryosundan birini seçebilir. Bu sayede kampanya hedeflemesi doğrudan insan yoğunluğu, alan genişliği ve süresine göre yapılır.
            </p>
          </div>

          <div className="grid gap-6 lg:grid-cols-3">
            {scenarios.map((scenario, index) => {
              const active = scenario.id === selectedScenario;
              return (
                <button
                  key={scenario.id}
                  onClick={() => goToDashboard(scenario.id)}
                  className={`group rounded-[2rem] border p-6 text-left transition duration-300 ${active ? 'border-cyan-400 bg-slate-800 shadow-xl shadow-cyan-500/10' : 'border-slate-700 bg-slate-950/90 hover:border-slate-500 hover:bg-slate-900'}`}>
                  <div className="flex items-center justify-between gap-4">
                    <div>
                      <p className="text-sm uppercase tracking-[0.25em] text-slate-400">{scenario.subtitle}</p>
                      <h2 className="mt-4 text-2xl font-semibold text-white">{scenario.label}</h2>
                    </div>
                    <div className={`flex h-12 w-12 items-center justify-center rounded-3xl text-lg font-bold ${active ? 'bg-cyan-500 text-slate-950' : 'bg-slate-900 text-slate-400'}`}>
                      {index + 1}
                    </div>
                  </div>
                  <p className="mt-5 text-slate-400">{scenario.description}</p>
                  <div className="mt-6 space-y-3 rounded-3xl border border-slate-800 bg-slate-950/80 px-4 py-4 text-sm text-slate-200">
                    {scenario.features.map((feature) => (
                      <p key={feature} className="font-medium">• {feature}</p>
                    ))}
                  </div>
                </button>
              );
            })}
          </div>

          <div className="mt-10 rounded-[2rem] border border-cyan-500/20 bg-slate-950/90 p-8 text-slate-200">
            <h3 className="text-xl font-semibold text-white">Seçilen Billboard</h3>
            <p className="mt-4 text-slate-400">{selected?.description}</p>
            <div className="mt-4 space-y-2 text-sm text-cyan-300">
              {selected?.features.map((feature) => (
                <p key={feature}>{feature}</p>
              ))}
            </div>
          </div>
        </section>

        <section className="grid gap-6 sm:grid-cols-2">
          <Link href="/dashboard" className="group rounded-[2rem] border border-slate-800 bg-slate-950/85 p-8 transition hover:-translate-y-1 hover:border-cyan-400/60 hover:bg-slate-900/95">
            <div className="flex items-center justify-between gap-4">
              <span className="text-sm uppercase tracking-[0.25em] text-cyan-400">Reklamveren</span>
              <span className="rounded-full bg-cyan-500/15 px-3 py-1 text-xs uppercase tracking-[0.2em] text-cyan-200">Kontrol Paneli</span>
            </div>
            <h2 className="mt-6 text-3xl font-semibold text-white">Marka Paneli</h2>
            <p className="mt-4 text-slate-400">MetaMask bağlantısı, teklif yönetimi ve reklam içeriği kontrolü. Akıllı kontratla biletlenen kampanyalarınızı yönetin.</p>
          </Link>

          <Link href="/billboard" className="group rounded-[2rem] border border-slate-800 bg-slate-950/85 p-8 transition hover:-translate-y-1 hover:border-violet-400/60 hover:bg-slate-900/95">
            <div className="flex items-center justify-between gap-4">
              <span className="text-sm uppercase tracking-[0.25em] text-violet-400">Ekran</span>
              <span className="rounded-full bg-violet-500/15 px-3 py-1 text-xs uppercase tracking-[0.2em] text-violet-200">Canlı Görünüm</span>
            </div>
            <h2 className="mt-6 text-3xl font-semibold text-white">Dijital Pano</h2>
            <p className="mt-4 text-slate-400">Tam ekran billboard simülasyonu. Kazanan reklamlar ve etkinlik geçmişi ile gerçek zamanlı gösterimi deneyimleyin.</p>
          </Link>
        </section>
      </div>
    </main>
  );
}
