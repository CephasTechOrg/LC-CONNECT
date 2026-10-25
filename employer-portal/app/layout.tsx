import type { Metadata } from 'next';
import { DM_Sans } from 'next/font/google';
import './globals.css';

// DM Sans, as in the student app and the admin portal: one product, one typeface.
const dmSans = DM_Sans({
  subsets: ['latin'],
  weight: ['400', '500', '600', '700'],
  variable: '--font-dm-sans',
});

export const metadata: Metadata = {
  title: 'Employer partner portal — Blueprint Bond',
  description: 'Blueprint Bond employer partner portal, powered by LC Connect',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className={`${dmSans.className} ${dmSans.variable}`}>{children}</body>
    </html>
  );
}
