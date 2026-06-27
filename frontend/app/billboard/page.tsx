export default function BillboardPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 text-white px-6 py-12">
      <div className="relative w-full max-w-5xl rounded-[2.5rem] border border-slate-800 bg-slate-950/95 p-10 shadow-[0_0_80px_rgba(15,23,42,0.65)]">
        <div className="absolute top-0 left-1/2 -translate-x-1/2 -translate-y-1/2 rounded-full bg-white/10 px-6 py-4 text-center shadow-[0_0_40px_rgba(255,255,255,0.08)]">
          <p className="text-xs uppercase tracking-[0.45em] text-cyan-300/80">Reklamveren Şirket Panosu</p>
        </div>

        <div className="mt-16 flex min-h-[360px] flex-col items-center justify-center text-center">
          <h1 className="text-[clamp(5rem,12vw,9rem)] font-black uppercase tracking-[-0.05em] text-white">
            ΣARFDAO
          </h1>
        </div>
      </div>
    </main>
  );
}
