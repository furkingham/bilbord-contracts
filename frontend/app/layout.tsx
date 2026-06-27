import './globals.css';
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Billboard dApp',
  description: 'Monad billboard auction frontend'
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="tr">
      <body>{children}</body>
    </html>
  );
}
