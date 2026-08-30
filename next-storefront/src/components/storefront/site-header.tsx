"use client";

import Image from "next/image";
import Link from "next/link";
import { Menu, Search, ShoppingBag, UserRound, WalletCards } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { Separator } from "@/components/ui/separator";

const navigation = [
  { label: "المتجر", href: "#storefront" },
  { label: "كيف يعمل؟", href: "#how-it-works" },
  { label: "المحفظة", href: "/wallet.html" },
  { label: "طلباتي", href: "/my-orders.html" },
];

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-40 border-b border-border/80 bg-background/90 backdrop-blur-xl">
      <div className="container-shell flex h-18 items-center justify-between gap-4">
        <Link href="/" className="shrink-0" aria-label="العودة إلى الرئيسية">
          <Image
            src="/brand/raizey-logo.svg"
            width={184}
            height={48}
            alt="RAIZEY STORE"
            priority
            className="h-auto w-36 sm:w-40"
          />
        </Link>

        <nav className="hidden items-center gap-7 lg:flex" aria-label="التنقل الرئيسي">
          {navigation.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="text-sm font-bold text-muted-foreground transition-colors hover:text-foreground"
            >
              {item.label}
            </Link>
          ))}
        </nav>

        <div className="flex items-center gap-1.5">
          <Button asChild variant="ghost" size="icon" className="hidden sm:inline-flex">
            <Link href="/search.html" aria-label="البحث في المتجر">
              <Search data-icon aria-hidden="true" />
            </Link>
          </Button>
          <Button asChild variant="ghost" size="icon">
            <Link href="/cart.html" aria-label="سلة المشتريات" className="relative">
              <ShoppingBag data-icon aria-hidden="true" />
              <span className="absolute right-2 top-2 size-1.5 rounded-full bg-primary" />
            </Link>
          </Button>
          <Button asChild variant="secondary" size="sm" className="hidden sm:inline-flex">
            <Link href="/login.html">
              <UserRound data-icon aria-hidden="true" />
              دخول
            </Link>
          </Button>

          <Sheet>
            <SheetTrigger asChild>
              <Button variant="ghost" size="icon" className="lg:hidden" aria-label="فتح القائمة">
                <Menu data-icon aria-hidden="true" />
              </Button>
            </SheetTrigger>
            <SheetContent side="right" dir="rtl">
              <SheetHeader className="border-b border-border pb-5 pl-14">
                <SheetTitle>قائمة RAIZEY</SheetTitle>
                <SheetDescription>كل ما تحتاجه للوصول السريع إلى المتجر وحسابك.</SheetDescription>
              </SheetHeader>
              <nav className="grid gap-1 px-4" aria-label="قائمة الهاتف">
                {navigation.map((item) => (
                  <SheetClose key={item.href} asChild>
                    <Link
                      href={item.href}
                      className="rounded-xl px-4 py-3.5 text-base font-bold transition-colors hover:bg-accent"
                    >
                      {item.label}
                    </Link>
                  </SheetClose>
                ))}
              </nav>
              <Separator className="my-1" />
              <div className="grid gap-3 px-5">
                <Button asChild variant="secondary" className="justify-start">
                  <Link href="/search.html">
                    <Search data-icon aria-hidden="true" />
                    البحث في المتجر
                  </Link>
                </Button>
                <Button asChild variant="secondary" className="justify-start">
                  <Link href="/wallet.html">
                    <WalletCards data-icon aria-hidden="true" />
                    المحفظة
                  </Link>
                </Button>
                <Button asChild className="mt-2">
                  <Link href="/login.html">تسجيل الدخول</Link>
                </Button>
              </div>
            </SheetContent>
          </Sheet>
        </div>
      </div>
    </header>
  );
}
