import type { Metadata } from 'next';
import { DM_Sans } from 'next/font/google';
import './globals.css';

// DM Sans, the student app's typeface, so the portal and the app look like one product.
const dmSans = DM_Sans({
  subsets: ['latin'],
  weight: ['400', '500', '600', '700'],
  variable: '--font-dm-sans',
});

export const metadata: Metadata = {
  title: 'LC Connect Admin',
  description: 'Campus Hub administration for Livingstone College',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className={`${dmSans.className} ${dmSans.variable}`}>{children}</body>
    </html>
  );
}
