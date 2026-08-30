import type { Metadata } from "next";
import { Cairo } from "next/font/google";
import "./globals.css";

const cairo = Cairo({
  variable: "--font-cairo",
  subsets: ["arabic", "latin"],
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL("https://raizey-store-qw.vercel.app"),
  title: {
    default: "RAIZEY STORE — شحناتك الرقمية بدون تعقيد",
    template: "%s — RAIZEY STORE",
  },
  description: "متجر رقمي للشحن والبطاقات والخدمات الإلكترونية بتجربة سريعة وآمنة.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ar" dir="rtl" className={`${cairo.variable} h-full scroll-smooth antialiased`}>
      <body className="flex min-h-full flex-col">{children}</body>
    </html>
  );
}
